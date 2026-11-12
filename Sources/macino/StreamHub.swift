//
//  StreamHub.swift — one persistent ffmpeg encoder feeding a byte-addressed
//  ring buffer that many HTTP readers can join at an exact offset.
//
//  Why byte-addressed? Picky TV players reconnect mid-stream and ask for a
//  specific byte offset. Serving them *anything else* (e.g. the newest data)
//  makes playback jump forward and the audio crackle. Requests for bytes that
//  do not exist yet block until the encoder has produced them.
//
//  MirrorCast for macOS · Powered by Greenstein.Design
//

import Foundation

final class StreamHub {

    static let chunkSize = 64 * 1024
    static let ringChunks = 768                       // ≈ 48 MiB history
    static let burstBytes = 320 * chunkSize           // ≈ 20 MiB head start

    private let condition = NSCondition()
    private var ring: [(offset: Int, data: Data)] = []
    private var producedTotal = 0
    private var stopping = false
    private var process: Process?

    private let ffmpeg: URL
    private let arguments: [String]

    /// Called when the encoder dies repeatedly (e.g. missing screen permission).
    var onEncoderFailure: ((String) -> Void)?

    var total: Int {
        condition.lock(); defer { condition.unlock() }
        return producedTotal
    }

    init(ffmpeg: URL, arguments: [String]) {
        self.ffmpeg = ffmpeg
        self.arguments = arguments
    }

    // MARK: Lifecycle

    func start() {
        let t = Thread { [weak self] in self?.pump() }
        t.name = "MirrorCast.Encoder"
        t.stackSize = 512 * 1024
        t.start()
    }

    func stop() {
        condition.lock()
        stopping = true
        condition.broadcast()
        condition.unlock()
        process?.terminate()
        process = nil
    }

    /// Blocks until `bytes` have been produced (or the timeout expires).
    @discardableResult
    func waitForBuffer(bytes: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if total >= bytes { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return total >= bytes
    }

    // MARK: Producer

    private func pump() {
        var consecutiveFailures = 0
        while true {
            condition.lock(); let done = stopping; condition.unlock()
            if done { return }

            let proc = Process()
            proc.executableURL = ffmpeg
            proc.arguments = arguments
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = FileHandle.nullDevice
            do { try proc.run() } catch {
                onEncoderFailure?("ffmpeg konnte nicht gestartet werden: \(error.localizedDescription)")
                return
            }
            process = proc
            let started = Date()
            let handle = out.fileHandleForReading

            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                condition.lock()
                if stopping { condition.unlock(); break }
                ring.append((offset: producedTotal, data: data))
                producedTotal += data.count
                while ring.count > Self.ringChunks { ring.removeFirst() }
                condition.broadcast()
                condition.unlock()
            }

            proc.terminate()
            condition.lock(); let stoppingNow = stopping; condition.unlock()
            if stoppingNow { return }

            // Encoder died on its own — most likely a missing screen-recording
            // permission or a disappearing capture device.
            if Date().timeIntervalSince(started) < 3 {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    onEncoderFailure?("Die Bildschirmaufnahme wurde abgelehnt. Bitte MirrorCast in "
                        + "Systemeinstellungen › Datenschutz & Sicherheit › Bildschirmaufnahme erlauben.")
                    return
                }
            } else {
                consecutiveFailures = 0
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: Consumer

    /// Streams from `wantByte` (or from a burst position when unknown/stale).
    /// `onBase` reports the absolute offset a fresh session starts at, so the
    /// caller can map the client's file offsets onto hub offsets.
    func stream(from wantByte: Int?,
                onBase: ((Int) -> Void)?,
                write: (Data) throws -> Void) rethrows {
        var position: Int
        condition.lock()
        let oldest = ring.first?.offset ?? producedTotal
        if let want = wantByte, want >= oldest {
            position = want                       // exact resume (may be in the future)
        } else if wantByte != nil {
            position = oldest                     // stale: continue with what we still have
        } else {
            position = max(oldest, producedTotal - Self.burstBytes)
            onBase?(position)
        }
        condition.unlock()

        while true {
            var pending: [Data] = []
            condition.lock()
            while producedTotal <= position && !stopping {
                condition.wait(until: Date().addingTimeInterval(5))
            }
            if stopping { condition.unlock(); return }
            let first = ring.first?.offset ?? producedTotal
            if position < first { position = first }
            for entry in ring where entry.offset + entry.data.count > position {
                if entry.offset >= position {
                    pending.append(entry.data)
                } else {
                    pending.append(entry.data.subdata(in: (position - entry.offset)..<entry.data.count))
                }
            }
            position = producedTotal
            condition.unlock()

            for block in pending { try write(block) }
        }
    }

    /// Newest `count` bytes — used to answer small bounded probe requests.
    func tail(_ count: Int) -> Data {
        condition.lock(); defer { condition.unlock() }
        var collected = Data()
        for entry in ring.reversed() {
            collected = entry.data + collected
            if collected.count >= count { break }
        }
        if collected.count >= count {
            return collected.suffix(count)
        }
        // Not enough material yet: pad with an MPEG padding packet.
        var padded = Data([0x00, 0x00, 0x01, 0xBE])
        let padLength = max(0, count - collected.count - 6)
        padded.append(UInt8((padLength >> 8) & 0xFF))
        padded.append(UInt8(padLength & 0xFF))
        padded.append(Data(repeating: 0xFF, count: padLength))
        padded.append(collected)
        return padded.prefix(count)
    }
}
