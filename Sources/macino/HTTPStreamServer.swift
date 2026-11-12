//
//  HTTPStreamServer.swift — serves the live stream to the TV while pretending
//  to be a large, finite file.
//
//  Two hard-won details:
//   * The advertised size must stay below 2^31 bytes. Many TV firmwares do
//     signed 32-bit math on Content-Length and reject anything bigger with
//     "file not supported".
//   * Small bounded Range requests (the player sniffing the tail of the
//     "file") must be answered with exactly that many bytes.
//
//  MirrorCast for macOS · Powered by Greenstein.Design
//

import Foundation

final class HTTPStreamServer {

    static let fakeSize = 1_900_000_000            // < 2^31, see note above
    static let fakeDuration = "0:36:00.000"

    private let port: UInt16
    private let hub: StreamHub
    private var listenFD: Int32 = -1
    private var running = false

    private let lock = NSLock()
    private var sessionBase: Int?                  // hub offset of client offset 0

    var mime: String = "video/mpeg"
    var dlnaFlags: String = ""
    var path: String = "/screen.mpg"
    var onLog: ((String) -> Void)?

    init(port: UInt16, hub: StreamHub) {
        self.port = port
        self.hub = hub
    }

    /// A fresh DLNA push means the TV starts counting file offsets at 0 again.
    func resetSession() {
        lock.lock(); sessionBase = nil; lock.unlock()
    }

    func start() throws {
        signal(SIGPIPE, SIG_IGN)
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw DLNAError.network("Socket konnte nicht erstellt werden.") }

        var yes: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(listenFD, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(listenFD)
            throw DLNAError.network("Port \(port) ist belegt — läuft MirrorCast bereits?")
        }
        guard listen(listenFD, 8) == 0 else {
            close(listenFD)
            throw DLNAError.network("Der Streaming-Port konnte nicht geöffnet werden.")
        }

        running = true
        let acceptThread = Thread { [weak self] in self?.acceptLoop() }
        acceptThread.name = "MirrorCast.HTTP"
        acceptThread.start()
    }

    func stop() {
        running = false
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
    }

    // MARK: Accept / serve

    private func acceptLoop() {
        while running {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { if running { usleep(100_000) }; continue }
            var timeout = timeval(tv_sec: 20, tv_usec: 0)
            setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let t = Thread { [weak self] in self?.serve(clientFD) }
            t.name = "MirrorCast.Client"
            t.start()
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        guard let request = readRequest(fd) else { return }
        let head = request.uppercased()
        let isHead = head.hasPrefix("HEAD")
        guard head.hasPrefix("GET") || isHead else {
            _ = writeAll(fd, Data("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n".utf8))
            return
        }

        var start = 0
        var end: Int?
        if let range = rxFirst(request, #"(?im)^Range:[ \t]*bytes=(\d+)-(\d*)"#, group: 1) {
            start = Int(range) ?? 0
            if let e = rxFirst(request, #"(?im)^Range:[ \t]*bytes=\d+-(\d+)"#), let v = Int(e) { end = v }
        }
        let hasRange = request.range(of: "Range:", options: .caseInsensitive) != nil
        let effectiveEnd = end ?? (Self.fakeSize - 1)

        var header = hasRange
            ? "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(start)-\(effectiveEnd)/\(Self.fakeSize)\r\n"
            : "HTTP/1.1 200 OK\r\n"
        header += "Content-Length: \(hasRange ? effectiveEnd - start + 1 : Self.fakeSize)\r\n"
        header += "Content-Type: \(mime)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "transferMode.dlna.org: Streaming\r\n"
        header += "contentFeatures.dlna.org: http-get:*:\(mime):\(dlnaFlags)\r\n"
        header += "Connection: close\r\n\r\n"
        guard writeAll(fd, Data(header.utf8)) else { return }
        if isHead { return }

        // Bounded probe (the player sniffing a small part of the "file").
        if let e = end, e - start + 1 <= 4 * 1024 * 1024 {
            let n = e - start + 1
            _ = writeAll(fd, hub.tail(n))
            onLog?("Sondierung beantwortet (\(n) Bytes)")
            return
        }

        var want: Int?
        lock.lock()
        if let base = sessionBase { want = base + start }
        lock.unlock()

        onLog?(want == nil ? "Neue Stream-Session" : "Fortsetzung ab Byte \(start)")
        try? hub.stream(from: want, onBase: { [weak self] base in
            guard let self else { return }
            self.lock.lock(); self.sessionBase = base - start; self.lock.unlock()
        }, write: { data in
            if !self.writeAll(fd, data) { throw DLNAError.network("client gone") }
        })
    }

    // MARK: Socket helpers

    private func readRequest(_ fd: Int32) -> String? {
        var buffer = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 2048)
        while buffer.count < 16 * 1024 {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            if let text = String(bytes: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                return text
            }
        }
        return String(bytes: buffer, encoding: .utf8)
    }

    @discardableResult
    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < data.count {
                let n = write(fd, base.advanced(by: sent), data.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}
