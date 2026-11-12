//
//  DLNA.swift — SSDP discovery, device description parsing and SOAP control
//  for UPnP/DLNA MediaRenderer devices (smart TVs).
//
//  MirrorCast for macOS · https://github.com/greensteindesign/mirrorcast-macos
//  Powered by Greenstein.Design (https://greenstein.design)
//

import Foundation

// MARK: - Model

struct DLNADevice: Equatable, Hashable {
    let uuid: String
    let ip: String
    let location: URL
    var name: String
    var controlURL: URL?
    var serviceType: String?

    static func == (a: DLNADevice, b: DLNADevice) -> Bool { a.uuid == b.uuid }
    func hash(into h: inout Hasher) { h.combine(uuid) }
}

enum DLNAError: LocalizedError {
    case noAVTransport(String)
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noAVTransport(let name): return "\(name) doesn't support DLNA playback."
        case .http(let code, let action):
            let operation: String
            switch action {
            case "SetAVTransportURI": operation = "load the stream"
            case "Play": operation = "start playback"
            case "Stop": operation = "stop playback"
            default: operation = "complete the request"
            }
            return "The TV couldn't \(operation) (UPnP error \(code))."
        case .network(let m): return m
        }
    }
}

// MARK: - Small regex helpers

func rxFirst(_ text: String, _ pattern: String, group: Int = 1) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern,
                                            options: [.caseInsensitive, .dotMatchesLineSeparators]),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          m.numberOfRanges > group,
          let r = Range(m.range(at: group), in: text) else { return nil }
    return String(text[r])
}

func rxAll(_ text: String, _ pattern: String, group: Int = 1) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern,
                                            options: [.caseInsensitive, .dotMatchesLineSeparators])
    else { return [] }
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        guard $0.numberOfRanges > group, let r = Range($0.range(at: group), in: text) else { return nil }
        return String(text[r])
    }
}

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - SSDP discovery

enum SSDP {

    /// Sends M-SEARCH to the SSDP multicast group and collects MediaRenderer replies.
    static func discover(timeout: TimeInterval = 3.0) -> [DLNADevice] {
        var found: [String: DLNADevice] = [:]
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var ttl: Int32 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1900).bigEndian
        addr.sin_addr.s_addr = inet_addr("239.255.255.250")

        let search = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
        \r\n
        """
        let payload = [UInt8](search.utf8)

        func send() {
            withUnsafePointer(to: &addr) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(fd, payload, payload.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        send()

        let deadline = Date().addingTimeInterval(timeout)
        var resent = false
        var buf = [UInt8](repeating: 0, count: 8192)

        while Date() < deadline {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 {
                if !resent {                       // one retry — UDP is lossy
                    resent = true
                    send()
                }
                continue
            }
            let text = String(decoding: buf[0..<n], as: UTF8.self)
            guard let locLine = rxFirst(text, #"(?im)^LOCATION:[ \t]*(\S+)"#),
                  let url = URL(string: locLine),
                  let uuid = rxFirst(text, #"uuid:([0-9a-fA-F\-]+)"#)?.lowercased()
            else { continue }
            if found[uuid] == nil {
                found[uuid] = DLNADevice(uuid: uuid, ip: url.host ?? "", location: url,
                                         name: url.host ?? uuid, controlURL: nil, serviceType: nil)
            }
        }
        return Array(found.values)
    }

    /// Fetches the device description and extracts name + AVTransport control endpoint.
    static func describe(_ device: DLNADevice) -> DLNADevice {
        var dev = device
        guard let xml = httpGetString(device.location, timeout: 6) else { return dev }

        if let name = rxFirst(xml, #"<friendlyName>([^<]*)</friendlyName>"#) {
            dev.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let base = "\(device.location.scheme ?? "http")://\(device.location.host ?? "")" +
                   (device.location.port.map { ":\($0)" } ?? "")

        for block in rxAll(xml, #"<service>(.*?)</service>"#) {
            guard let type = rxFirst(block, #"<serviceType>([^<]*)</serviceType>"#),
                  type.contains("AVTransport"),
                  var ctrl = rxFirst(block, #"<controlURL>([^<]*)</controlURL>"#) else { continue }
            ctrl = ctrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ctrl.lowercased().hasPrefix("http") {
                ctrl = base + (ctrl.hasPrefix("/") ? ctrl : "/" + ctrl)
            }
            dev.controlURL = URL(string: ctrl)
            dev.serviceType = type
            break
        }
        return dev
    }
}

// MARK: - Synchronous HTTP helpers

func httpGetString(_ url: URL, timeout: TimeInterval) -> String? {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    req.setValue("macino (macOS)", forHTTPHeaderField: "User-Agent")
    var result: String?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, _, _ in
        if let d = data { result = String(decoding: d, as: UTF8.self) }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + timeout + 2)
    return result
}

// MARK: - AVTransport control

struct AVTransport {
    let device: DLNADevice

    @discardableResult
    func call(_ action: String, body: String = "") throws -> String {
        guard let url = device.controlURL, let stype = device.serviceType else {
            throw DLNAError.noAVTransport(device.name)
        }
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="\(stype)"><InstanceID>0</InstanceID>\(body)</u:\(action)></s:Body>
        </s:Envelope>
        """
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(stype)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        req.setValue("macino (macOS)", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(envelope.utf8)

        var text = ""
        var status = 0
        var netError: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let e = err { netError = e.localizedDescription }
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let d = data { text = String(decoding: d, as: UTF8.self) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 13)

        if let e = netError { throw DLNAError.network(e) }
        if status >= 400 {
            let code = Int(rxFirst(text, #"<errorCode>(\d+)</errorCode>"#) ?? "") ?? status
            throw DLNAError.http(code, action)
        }
        return text
    }

    /// Points the TV at `url` and starts playback.
    func play(url: String, title: String, mime: String, dlnaFlags: String,
              size: Int, duration: String) throws {
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">\
        <item id="0" parentID="-1" restricted="1"><dc:title>\(xmlEscape(title))</dc:title>\
        <upnp:class>object.item.videoItem</upnp:class>\
        <res protocolInfo="http-get:*:\(mime):\(dlnaFlags)" size="\(size)" \
        duration="\(duration)">\(xmlEscape(url))</res></item></DIDL-Lite>
        """
        _ = try? call("Stop")
        Thread.sleep(forTimeInterval: 1.0)
        try call("SetAVTransportURI",
                 body: "<CurrentURI>\(xmlEscape(url))</CurrentURI>" +
                       "<CurrentURIMetaData>\(xmlEscape(didl))</CurrentURIMetaData>")
        try call("Play", body: "<Speed>1</Speed>")
    }

    func stop() { _ = try? call("Stop") }

    /// PLAYING / TRANSITIONING / STOPPED / PAUSED_PLAYBACK / NO_MEDIA_PRESENT
    func transportState() -> String? {
        guard let xml = try? call("GetTransportInfo") else { return nil }
        return rxFirst(xml, #"<CurrentTransportState>([^<]*)</CurrentTransportState>"#)
    }
}
