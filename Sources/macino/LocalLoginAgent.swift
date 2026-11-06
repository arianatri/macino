import Foundation
import Security

/// A user-owned, opt-in login configuration for locally/ad-hoc signed builds.
/// No root daemon, KeepAlive, authorization bypass, or launchctl enable override.
enum LocalLoginAgent {
    static let label = "local.macino.login"
    static let marker = "Managed by macino: launch once at user login"
    static var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static func isAdHoc(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let flags = (info as? [String: Any])?[kSecCodeInfoFlags as String] as? NSNumber else { return false }
        return flags.uint32Value & 0x0002 != 0 // kSecCodeSignatureAdhoc, documented in CSCommon.h
    }
    static func savedApp(file: URL = file) throws -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard let p = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              p["Label"] as? String == label, p["Comment"] as? String == marker,
              p["RunAtLoad"] as? Bool == true,
              let args = p["ProgramArguments"] as? [String], args.count == 3,
              args[0] == "/usr/bin/open", args[1] == "-g", args[2].hasSuffix(".app") else {
            throw AppError.message("The login configuration file is not managed by macino; it was left unchanged: \(file.path)")
        }
        return args[2]
    }
    static func save(app: URL, file: URL = file) throws {
        guard !app.path.hasPrefix("/Volumes/"), app.pathExtension == "app",
              let executable = Bundle(url: app)?.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppError.message("Install macino on a local disk before enabling launch at login.")
        }
        if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw AppError.message("Login configuration is a symbolic link; it was left unchanged.") }
        _ = try savedApp(file: file) // Refuse to replace an unrelated file.
        let plist: [String: Any] = ["Label": label, "Comment": marker,
            "ProgramArguments": ["/usr/bin/open", "-g", app.path], "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua", "AssociatedBundleIdentifiers": ["local.macino"]]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: file, options: .atomic)
        guard try savedApp(file: file) == app.path else { throw AppError.message("Login configuration did not verify after saving.") }
    }
    static func remove(file: URL = file) throws {
        guard try savedApp(file: file) != nil else { return }
        try FileManager.default.removeItem(at: file)
    }
}
