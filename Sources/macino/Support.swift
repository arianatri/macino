import Foundation
import AppKit

struct CommandResult { let output: String; let code: Int32 }
enum Shell {
    static func run(_ path: String, _ args: [String] = []) throws -> CommandResult {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return CommandResult(output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), code: p.terminationStatus)
    }
    static func checked(_ path: String, _ args: [String] = []) throws -> String {
        let r = try run(path, args); guard r.code == 0 else { throw AppError.message(r.output) }; return r.output
    }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func admin(_ commands: [[String]]) throws {
        let command = commands.map { $0.map(quote).joined(separator: " ") }.joined(separator: " && ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        _ = try checked("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }
}
enum AppError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let m) = self { return m }; return nil } }
func bytes(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .binary) }
func sysctlString(_ key: String) -> String {
    var size = 0; sysctlbyname(key, nil, &size, nil, 0); guard size > 0 else { return "Unavailable" }
    var buffer = [CChar](repeating: 0, count: size); sysctlbyname(key, &buffer, &size, nil, 0); return String(cString: buffer)
}
