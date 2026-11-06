import AppKit
import Foundation

struct AndroidUSBDevice: Decodable, Identifiable {
    let bus: UInt32
    let device: UInt32
    let name: String
    var id: String { "\(bus):\(device)" }
}
struct AndroidStorage: Decodable, Identifiable {
    let id: UInt32
    let name: String
    let capacity: UInt64
    let free: UInt64
}
struct AndroidFile: Decodable, Identifiable {
    let id: UInt32
    let name: String
    let size: UInt64
    let folder: Bool
}
struct AndroidScreenDevice: Identifiable, Equatable {
    let id: String
    let state: String
    let name: String
    var authorized: Bool { state == "device" }
    var wireless: Bool { id.contains(":") || id.contains("_adb-tls-") || id.contains("._tcp") }
    static func parse(_ output: String) -> [Self] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, ["device", "unauthorized", "offline", "no"].contains(fields[1]) else { return nil }
            let name = fields.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? fields[0]
            return Self(id: fields[0], state: fields[1], name: name)
        }
    }
}
private struct MTPResponse: Decodable {
    var devices: [AndroidUSBDevice]?
    var storages: [AndroidStorage]?
    var serial: String?
    var files: [AndroidFile]?
    var error: String?
    var ok: Bool?
}
enum AndroidTools {
    static var directory: URL { Bundle.main.resourceURL!.appendingPathComponent("Android", isDirectory: true) }
    static func binary(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw AppError.message("Android tools are missing. Install the latest macino DMG.") }
        return url
    }
    /// Disk-backed output prevents full USB/ADB pipes from blocking a subprocess.
    static func run(_ executable: URL, arguments: [String] = [], input: Data? = nil, timeout: TimeInterval = 60) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(executable, arguments: arguments, input: input, timeout: timeout)
        }.value
    }
    private static func runBlocking(_ executable: URL, arguments: [String], input: Data?, timeout: TimeInterval) throws -> Data {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("macino-android-" + UUID().uuidString)
            try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: work) }
            let out = work.appendingPathComponent("out"), err = work.appendingPathComponent("err"), request = work.appendingPathComponent("request")
            fm.createFile(atPath: out.path, contents: nil); fm.createFile(atPath: err.path, contents: nil)
            try (input ?? Data()).write(to: request)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.path)
            let stdout = try FileHandle(forWritingTo: out), stderr = try FileHandle(forWritingTo: err), stdin = try FileHandle(forReadingFrom: request)
            defer { try? stdout.close(); try? stderr.close(); try? stdin.close() }
            let process = Process(); process.executableURL = executable; process.arguments = arguments
            process.standardOutput = stdout; process.standardError = stderr; process.standardInput = stdin
            let done = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in done.signal() }
            try process.run()
            if done.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                if done.wait(timeout: .now() + 2) == .timedOut { if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit() }
                throw AppError.message("The phone did not respond in time. Reconnect USB and refresh. An interrupted upload may leave a partial file on the phone.")
            }
            let data = try Data(contentsOf: out)
            guard data.count < 32 * 1024 * 1024 else { throw AppError.message("This folder has too many entries. Choose a smaller folder.") }
            if process.terminationStatus != 0 && executable.lastPathComponent != "macino-mtp" {
                let detail = String(data: (try? Data(contentsOf: err)) ?? Data(), encoding: .utf8) ?? ""
                throw AppError.message(detail.isEmpty ? "Android tool exited with an error." : String(detail.suffix(1500)))
            }
            guard !data.isEmpty else { throw AppError.message("Android tool returned no response. Reconnect the phone and try again.") }
            return data
    }
}

@MainActor final class AndroidScreenSession: ObservableObject {
    static let shared = AndroidScreenSession()
    @Published var running = false
    @Published var message: String?
    private var process: Process?
    private var log: URL?
    private var handle: FileHandle?
    func start(serial: String) {
        guard !running else { return }
        do {
            let p = Process(); p.executableURL = try AndroidTools.binary("scrcpy")
            p.arguments = ["--serial", serial, "--window-title", "macino • Android screen", "--no-control", "--no-audio", "--no-clipboard-autosync", "--max-size=1600", "--max-fps=30"]
            var environment = ProcessInfo.processInfo.environment
            environment["ADB"] = try AndroidTools.binary("adb").path
            environment["SCRCPY_SERVER_PATH"] = AndroidTools.directory.appendingPathComponent("scrcpy-server").path
            p.environment = environment
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("macino-screen-" + UUID().uuidString + ".log")
            FileManager.default.createFile(atPath: path.path, contents: nil)
            let output = try FileHandle(forWritingTo: path)
            p.standardOutput = output; p.standardError = output; p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { [weak self] finished in
                Task { @MainActor in
                    guard let self, self.process === finished else { return }
                    let detail = String(data: (try? Data(contentsOf: path)) ?? Data(), encoding: .utf8) ?? ""
                    if finished.terminationStatus != 0 && finished.terminationReason == .exit { self.message = String(detail.suffix(1800)) }
                    self.running = false; self.process = nil
                    try? self.handle?.close(); self.handle = nil
                    try? FileManager.default.removeItem(at: path); self.log = nil
                }
            }
            process = p; log = path; handle = output
            try p.run(); running = true; message = nil
        } catch {
            message = error.localizedDescription; process = nil; running = false
            try? handle?.close(); handle = nil
            if let log { try? FileManager.default.removeItem(at: log) }; log = nil
        }
    }
    func stop() { if let process, process.isRunning { process.terminate() } }
}

@MainActor final class AndroidModel: ObservableObject {
    @Published var devices: [AndroidUSBDevice] = []
    @Published var selectedDevice = ""
    @Published var storages: [AndroidStorage] = []
    @Published var selectedStorage: UInt32 = 0
    @Published var files: [AndroidFile] = []
    @Published var folders: [(id: UInt32, name: String)] = []
    @Published var busy = false
    @Published var status = "Connect an unlocked Android phone using USB."
    @Published var message: String?
    @Published var screenDevices: [AndroidScreenDevice] = []
    @Published var selectedScreen = ""
    @Published var screenBusy = false
    @Published var screenWiFi = false
    @Published var wifiHost = ""
    @Published var wifiPort = ""
    @Published var pairingPort = ""
    @Published var pairingCode = ""
    var visibleScreens: [AndroidScreenDevice] { screenDevices.filter { $0.wireless == screenWiFi } }
    var selectedReady: Bool { visibleScreens.contains { $0.id == selectedScreen && $0.authorized } }
    func selectScreenTransport() { selectedScreen = visibleScreens.first?.id ?? "" }

    @Published var screenStatus = "USB debugging is needed for screen sharing."
    private var serial = ""
    private var scanned = false
    var parent: UInt32 { folders.last?.id ?? UInt32.max }
    var connected: Bool { !storages.isEmpty }
    var path: String { (["Phone"] + folders.map(\.name)).joined(separator: " / ") }
    private func request(_ operation: String, extra: [String: Any] = [:]) async throws -> MTPResponse {
        var q: [String: Any] = ["operation": operation]
        if operation != "devices" {
            guard let device = devices.first(where: { $0.id == selectedDevice }) else { throw AppError.message("Select a phone and connect first.") }
            q["bus"] = device.bus; q["device"] = device.device
            q["storage"] = selectedStorage; q["parent"] = parent
            if !serial.isEmpty { q["serial"] = serial }
        }
        q.merge(extra) { _, new in new }
        let result = try await AndroidTools.run(AndroidTools.binary("macino-mtp"), input: JSONSerialization.data(withJSONObject: q), timeout: operation == "upload" || operation == "download" ? 1800 : 60)
        let response = try JSONDecoder().decode(MTPResponse.self, from: result)
        if let error = response.error { throw AppError.message(error) }
        return response
    }
    func firstScan() { guard !scanned else { return }; scanned = true; scan() }
    func scan() {
        guard !busy else { return }; busy = true; status = "Looking for MTP phones…"
        Task {
            defer { busy = false }
            do {
                let response = try await request("devices")
                devices = response.devices ?? []; selectedDevice = devices.first?.id ?? ""
                resetConnection()
                status = devices.isEmpty ? "No MTP phone found. Unlock it and select File transfer on USB." : "Select your phone, then Connect."
            } catch { resetConnection(); devices = []; selectedDevice = ""; message = error.localizedDescription; status = "Phone discovery failed." }
        }
    }
    func resetConnection() { storages = []; selectedStorage = 0; folders = []; files = []; serial = "" }
    func connect() {
        guard !busy else { return }; resetConnection(); busy = true; status = "Connecting…"
        Task {
            defer { busy = false }
            do {
                let response = try await request("storage"); serial = response.serial ?? ""
                storages = response.storages ?? []; selectedStorage = storages.first?.id ?? 0
                guard !storages.isEmpty else { throw AppError.message("The phone has no accessible storage. Unlock it and allow file access.") }
                try await loadFiles()
            } catch { resetConnection(); message = error.localizedDescription; status = "Connection failed." }
        }
    }
    private func loadFiles() async throws {
        files = []
        let response = try await request("list")
        files = (response.files ?? []).sorted { $0.folder != $1.folder ? $0.folder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        status = "\(files.count) items • USB / MTP"
    }
    func browse(_ folder: AndroidFile? = nil, up: Bool = false, storageChanged: Bool = false) {
        guard !busy, connected else { return }; busy = true
        if storageChanged { folders = [] }
        if up && !folders.isEmpty { folders.removeLast() }
        if let folder, folder.folder { folders.append((folder.id, folder.name)) }
        Task {
            defer { busy = false }
            do { try await loadFiles() } catch { files = []; message = error.localizedDescription; status = "Refresh to reconnect." }
        }
    }
    func download(_ file: AndroidFile) {
        guard !busy, !file.folder else { return }
        let picker = NSSavePanel(); picker.nameFieldStringValue = URL(fileURLWithPath: file.name).lastPathComponent
        picker.title = "Save from Android"
        picker.message = "Choose a new filename. Existing files are preserved."
        guard picker.runModal() == .OK, let destination = picker.url else { return }
        busy = true; status = "Downloading \(file.name)…"
        // A same-directory staging file avoids overwriting an existing destination.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".macino-" + UUID().uuidString + ".partial")
        Task {
            defer { busy = false; try? FileManager.default.removeItem(at: staging) }
            do {
                _ = try await request("download", extra: ["item": file.id, "name": file.name, "path": staging.path])
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw AppError.message("The destination already exists. Choose a new filename; it has not been overwritten.") }
                try FileManager.default.moveItem(at: staging, to: destination)
                status = "Saved \(file.name)"; NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { status = "Download failed."; message = error.localizedDescription }
        }
    }
    func upload() {
        guard !busy, connected else { return }
        let picker = NSOpenPanel(); picker.canChooseFiles = true; picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.title = "Send a file to Android"
        guard picker.runModal() == .OK, let source = picker.url else { return }
        busy = true; status = "Sending \(source.lastPathComponent)…"
        Task {
            defer { busy = false }
            do { _ = try await request("upload", extra: ["path": source.path]); try await loadFiles(); status = "Sent \(source.lastPathComponent)" }
            catch { status = "Upload failed."; message = error.localizedDescription }
        }
    }
    func refreshScreens() {
        guard !screenBusy else { return }; screenBusy = true; screenStatus = "Checking authorized phones…"
        Task {
            defer { screenBusy = false }
            do {
                let result = try await AndroidTools.run(AndroidTools.binary("adb"), arguments: ["devices", "-l"], timeout: 15)
                screenDevices = AndroidScreenDevice.parse(String(decoding: result, as: UTF8.self))
                if !visibleScreens.contains(where: { $0.id == selectedScreen }) { selectScreenTransport() }
                screenStatus = visibleScreens.isEmpty ? (screenWiFi ? "Connect using the IP and port shown on your phone." : "Enable USB debugging, connect USB, then Refresh.") : (selectedReady ? "Phone ready. Tap Share screen." : "Approve debugging on your phone, then Refresh.")
            } catch { screenDevices = []; selectedScreen = ""; screenStatus = error.localizedDescription }
        }
    }
    static func wifiEndpoint(host: String, port: String) throws -> String {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        var v4 = in_addr(), v6 = in6_addr()
        let ipv4 = inet_pton(AF_INET, host, &v4) == 1
        let ipv6 = inet_pton(AF_INET6, host, &v6) == 1
        guard ipv4 || ipv6, !port.isEmpty, port.allSatisfy({ $0.isASCII && $0.isNumber }), let number = UInt16(port), number > 0 else {
            throw AppError.message("Enter the phone’s IP address and a port from 1 to 65535, as shown in Wireless debugging.")
        }
        return "\(ipv6 ? "[" + host + "]" : host):\(number)"
    }
    func pairWiFi() {
        guard !screenBusy else { return }
        do {
            let endpoint = try Self.wifiEndpoint(host: wifiHost, port: pairingPort)
            let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.count == 6 && code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw AppError.message("Enter the six-digit pairing code displayed on your phone.") }
            pairingCode = ""; screenBusy = true; screenStatus = "Pairing with your phone…"
            Task {
                defer { screenBusy = false }
                do {
                    // Keep the pairing code off the process argument list and out of preferences.
                    let data = try await AndroidTools.run(AndroidTools.binary("adb"), arguments: ["pair", endpoint], input: Data((code + "\n").utf8), timeout: 30)
                    guard String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("successfully paired") else { throw AppError.message("Pairing was not accepted.") }
                    screenStatus = "Paired. Enter the connection port from the main Wireless debugging screen, then Connect."
                } catch { screenStatus = "Pairing failed. Keep the pairing-code screen open and try its new code and port." }
            }
        } catch { screenStatus = error.localizedDescription }
    }
    func connectWiFi() {
        guard !screenBusy else { return }
        do {
            let endpoint = try Self.wifiEndpoint(host: wifiHost, port: wifiPort)
            screenBusy = true; screenStatus = "Connecting over Wi-Fi…"
            Task {
                defer { screenBusy = false }
                do {
                    let result = try await AndroidTools.run(AndroidTools.binary("adb"), arguments: ["connect", endpoint], timeout: 20)
                    let text = String(decoding: result, as: UTF8.self)
                    guard text.localizedCaseInsensitiveContains("connected to") else { throw AppError.message("Connection failed. Check the connection port; it is different from the pairing port.") }
                    let data = try await AndroidTools.run(AndroidTools.binary("adb"), arguments: ["devices", "-l"], timeout: 15)
                    screenDevices = AndroidScreenDevice.parse(String(decoding: data, as: UTF8.self))
                    selectedScreen = visibleScreens.first(where: { $0.id == endpoint })?.id ?? visibleScreens.first(where: { $0.authorized })?.id ?? ""
                    screenStatus = selectedReady ? "Wi-Fi connected. Tap Share screen." : "Waiting for phone authorization. Tap Refresh after approving."
                } catch { screenStatus = error.localizedDescription }
            }
        } catch { screenStatus = error.localizedDescription }
    }
    func disconnectWiFi() {
        guard !screenBusy, let device = visibleScreens.first(where: { $0.id == selectedScreen }), device.wireless else { return }
        screenBusy = true
        Task {
            defer { screenBusy = false }
            do {
                _ = try await AndroidTools.run(AndroidTools.binary("adb"), arguments: ["disconnect", device.id], timeout: 15)
                screenDevices.removeAll { $0.id == device.id }; selectScreenTransport()
                screenStatus = "Wi-Fi disconnected. Pairing is kept; use Forget on the phone to revoke it."
            } catch { screenStatus = error.localizedDescription }
        }
    }

}
