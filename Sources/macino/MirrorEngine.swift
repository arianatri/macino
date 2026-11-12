//
//  MirrorEngine.swift — glues capture, streaming and DLNA control together.
//
//  MirrorCast for macOS · Powered by Greenstein.Design
//

import Foundation

enum MirrorState {
    case idle
    case preparing(String)
    case mirroring(String)
    case failed(String)
}

final class MirrorEngine {

    static let streamPort: UInt16 = 8790

    private(set) var state: MirrorState = .idle {
        didSet { DispatchQueue.main.async { self.onState?(self.state) } }
    }
    var onState: ((MirrorState) -> Void)?
    var onLog: ((String) -> Void)?

    private var hub: StreamHub?
    private var server: HTTPStreamServer?
    private var transport: AVTransport?
    private var watchdog: DispatchSourceTimer?
    private var streamURL: String = ""
    private var profile: MirrorProfile = .all[0]
    private var stoppedByUser = false
    private var audioCapture: SystemAudioCapture?

    var isRunning: Bool {
        if case .idle = state { return false }
        if case .failed = state { return false }
        return true
    }

    // MARK: - Environment

    /// ffmpeg is not bundled (licensing); we locate a user-installed copy.
    static func findFFmpeg() -> URL? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg",
                          "/opt/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Raw output of `ffmpeg -f avfoundation -list_devices true -i ""`.
    static func deviceListing() -> String {
        guard let ffmpeg = findFFmpeg() else { return "" }
        let proc = Process()
        proc.executableURL = ffmpeg
        proc.arguments = ["-f", "avfoundation", "-list_devices", "true", "-i", ""]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = FileHandle.nullDevice
        do { try proc.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func screenIndex(from listing: String) -> String {
        rxFirst(listing, #"\[(\d+)\]\s+Capture screen 0"#) ?? "0"
    }

    private static func localAddress(towards host: String) -> String {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        defer { if fd >= 0 { close(fd) } }
        guard fd >= 0 else { return "127.0.0.1" }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard ok == 0 else { return "127.0.0.1" }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &local) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        guard got == 0 else { return "127.0.0.1" }
        return String(cString: inet_ntoa(local.sin_addr))
    }

    // MARK: - Control

    func start(device: DLNADevice, profile: MirrorProfile, captureAudio: Bool) {
        guard !isRunning else { return }
        stoppedByUser = false
        self.profile = profile
        state = .preparing("Starting the stream…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let ffmpeg = Self.findFFmpeg() else {
                self.state = .failed("FFmpeg isn't installed. Install it with Homebrew, then reopen macino.")
                return
            }
            let described = device.controlURL == nil ? SSDP.describe(device) : device
            guard described.controlURL != nil else {
                self.state = .failed("\(described.name) doesn't support DLNA playback, so macino can't start a stream on it.")
                return
            }
            let transport = AVTransport(device: described)
            self.transport = transport

            let listing = Self.deviceListing()
            let screen = Self.screenIndex(from: listing)
            let fifo = captureAudio ? FileManager.default.temporaryDirectory.appendingPathComponent("macino-audio-\(UUID().uuidString).pcm") : nil

            let hub = StreamHub(ffmpeg: ffmpeg,
                                arguments: profile.ffmpegArguments(screenIndex: screen, audioFIFOPath: fifo?.path))
            hub.onEncoderFailure = { [weak self] message in
                self?.state = .failed(message)
                self?.teardown()
            }
            self.hub = hub
            hub.start()
            if let fifo {
                let capture = SystemAudioCapture(fifoURL: fifo)
                capture.onFailure = { [weak self] message in
                    self?.fail(message)
                }
                self.audioCapture = capture
                capture.start()
            }

            let server = HTTPStreamServer(port: Self.streamPort, hub: hub)
            server.mime = profile.mime
            server.dlnaFlags = profile.dlnaFlags
            server.onLog = { [weak self] in self?.onLog?($0) }
            do {
                try server.start()
            } catch {
                self.state = .failed(error.localizedDescription)
                self.teardown()
                return
            }
            self.server = server

            // Give the TV a ~20 s cushion before it starts pulling: these
            // players buffer very little themselves and stutter otherwise.
            self.state = .preparing("Getting the stream ready for your TV…")
            hub.waitForBuffer(bytes: StreamHub.burstBytes, timeout: 60)
            if self.stoppedByUser { return }

            let ip = Self.localAddress(towards: described.ip)
            self.streamURL = "http://\(ip):\(Self.streamPort)/screen.\(profile.fileExtension)"
            self.onLog?("Stream URL: \(self.streamURL)")

            do {
                try self.push()
            } catch {
                self.state = .failed(error.localizedDescription)
                self.teardown()
                return
            }
            self.state = .mirroring(described.name)
            self.startWatchdog()
        }
    }

    func stop() {
        stoppedByUser = true
        transport?.stop()
        teardown()
        state = .idle
    }

    private func fail(_ message: String) {
        guard !stoppedByUser else { return }
        stoppedByUser = true
        transport?.stop()
        teardown()
        state = .failed(message)
    }

    /// Starts capture + HTTP server without pushing to a TV. Used to verify the
    /// local half of the pipeline:
    ///   MIRRORCAST_SELFTEST=1 open -a MirrorCast
    ///   curl -r 0-2000000 http://localhost:8790/screen.mpg -o probe.mpg
    func startSelfTest(profile: MirrorProfile, captureAudio: Bool) {
        guard !isRunning, let ffmpeg = Self.findFFmpeg() else {
            state = .failed("FFmpeg isn't installed, so the stream check can't start.")
            return
        }
        self.profile = profile
        stoppedByUser = false
        let listing = Self.deviceListing()
        let hub = StreamHub(ffmpeg: ffmpeg,
                            arguments: profile.ffmpegArguments(
                                screenIndex: Self.screenIndex(from: listing),
                                audioFIFOPath: nil))
        hub.onEncoderFailure = { [weak self] in self?.state = .failed($0) }
        self.hub = hub
        hub.start()
        let server = HTTPStreamServer(port: Self.streamPort, hub: hub)
        server.mime = profile.mime
        server.dlnaFlags = profile.dlnaFlags
        self.server = server
        do { try server.start() } catch {
            state = .failed(error.localizedDescription); return
        }
        state = .preparing("Stream check ready on port \(Self.streamPort).")
    }

    private func push() throws {
        guard let transport else { return }
        server?.resetSession()
        try transport.play(url: streamURL,
                           title: "Mac screen",
                           mime: profile.mime,
                           dlnaFlags: profile.dlnaFlags,
                           size: HTTPStreamServer.fakeSize,
                           duration: HTTPStreamServer.fakeDuration)
    }

    private func teardown() {
        watchdog?.cancel(); watchdog = nil
        audioCapture?.stop(); audioCapture = nil
        server?.stop(); server = nil
        hub?.stop(); hub = nil
    }

    /// Re-pushes if the TV drops the session (it does so after seeking, after
    /// the advertised duration, or when it briefly loses the stream).
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        var failures = 0
        timer.setEventHandler { [weak self] in
            guard let self, let transport = self.transport, !self.stoppedByUser else { return }
            let current = transport.transportState() ?? "?"
            switch current {
            case "PLAYING":
                failures = 0
            case "STOPPED", "NO_MEDIA_PRESENT":
                failures += 1
                if failures > 8 {
                    self.state = .failed("The TV stopped the stream. Try a different video format.")
                    self.teardown()
                    return
                }
                self.onLog?("The TV stopped playback. Trying to reconnect…")
                try? self.push()
            default:
                break
            }
        }
        timer.resume()
        watchdog = timer
    }
}
