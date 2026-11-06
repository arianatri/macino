import Foundation

struct InstallFailure: LocalizedError { let errorDescription: String?; init(_ message: String) { errorDescription = message } }
struct InstallResult { let app: URL; let backup: URL? }
enum InstallTransaction {
    static func verify(_ app: URL) throws {
        guard Bundle(url: app)?.bundleIdentifier == "local.macino" else { throw InstallFailure("This is not the macino application included with this installer.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        let output = Pipe(); process.standardError = output; process.standardOutput = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallFailure("Application verification failed: " + String(decoding: data, as: UTF8.self)) }
    }
    static func install(source: URL, directory: URL) throws -> InstallResult {
        try verify(source)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("macino.app")
        guard source.resolvingSymlinksInPath().standardizedFileURL != target.resolvingSymlinksInPath().standardizedFileURL else { return InstallResult(app: target, backup: nil) }
        if fm.fileExists(atPath: target.path), Bundle(url: target)?.bundleIdentifier != "local.macino" { throw InstallFailure("A different item named macino.app already exists at the destination. It was left unchanged.") }
        let stage = directory.appendingPathComponent(".macino-install-\(UUID().uuidString).app")
        defer { if fm.fileExists(atPath: stage.path) { try? fm.removeItem(at: stage) } }
        let copy = Process(); copy.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); copy.arguments = [source.path, stage.path]
        let output = Pipe(); copy.standardError = output; copy.standardOutput = output
        try copy.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); copy.waitUntilExit()
        guard copy.terminationStatus == 0 else { throw InstallFailure("Could not copy macino: " + String(decoding: data, as: UTF8.self)) }
        try verify(stage)
        var backup: URL?
        if fm.fileExists(atPath: target.path) {
            let previous = directory.appendingPathComponent(".macino-previous-\(UUID().uuidString).app")
            try fm.moveItem(at: target, to: previous); backup = previous
        }
        do { try fm.moveItem(at: stage, to: target) }
        catch { if let backup { try? fm.moveItem(at: backup, to: target) }; throw error }
        return InstallResult(app: target, backup: backup)
    }
    static func selfTest(source: URL) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("macino-installer-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        let first = try install(source: source, directory: temp)
        try verify(first.app)
        guard first.backup == nil else { throw InstallFailure("Unexpected first-install backup") }
        print("PASS verified copy into isolated installation folder")
        let update = try install(source: source, directory: temp)
        guard let backup = update.backup else { throw InstallFailure("Missing update backup") }
        try verify(backup); try verify(update.app)
        print("PASS update preserves the previous signed app")
        let other = temp.appendingPathComponent("other")
        try fm.createDirectory(at: other.appendingPathComponent("macino.app"), withIntermediateDirectories: true)
        do { _ = try install(source: source, directory: other); throw InstallFailure("Unrelated target was not rejected") }
        catch let error as InstallFailure where error.errorDescription?.contains("different item") == true { print("PASS unrelated destination is preserved") }
    }
}
