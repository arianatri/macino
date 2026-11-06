import Foundation

struct ProcessDiagnostic {
    let parent: String
    let state: String
    let elapsed: String
    let priority: String
    let connections: String
}
enum ProcessDiagnostics {
    static func inspect(_ row: ProcessRow) throws -> ProcessDiagnostic {
        func validate() throws {
            guard let current = try ProcessManager.sample().first(where: { $0.id == row.id }),
                  current.started == row.started, current.command == row.command else {
                throw AppError.message("Process exited or changed. Reopen Process Info.")
            }
        }
        try validate()
        let output = try Shell.checked("/bin/ps", ["-p", String(row.id), "-o", "ppid=,state=,etime=,nice="])
        let parts = output.split(whereSeparator: \.isWhitespace)
        guard parts.count == 4, let parentID = Int32(parts[0]) else { throw AppError.message("Process details unavailable.") }
        let parentName = (try? Shell.checked("/bin/ps", ["-p", String(parentID), "-o", "comm="])) ?? "Exited"
        // -nP avoids DNS/service-name lookups; -S bounds kernel waits.
        let sockets = try Shell.run("/usr/sbin/lsof", ["-nP", "-S", "2", "-a", "-p", String(row.id), "-i"])
        let connections: String
        if sockets.code == 0 { connections = sockets.output.components(separatedBy: .newlines).prefix(250).joined(separator: "\n") }
        else if sockets.code == 1 && sockets.output.isEmpty { connections = "No visible TCP/UDP connections." }
        else { connections = "Connections unavailable: " + sockets.output }
        try validate()
        return ProcessDiagnostic(parent: "\(parentID) · \(URL(fileURLWithPath: parentName).lastPathComponent)", state: String(parts[1]), elapsed: String(parts[2]), priority: String(parts[3]), connections: connections)
    }
}
enum ProcessReport {
    struct Entry: Encodable {
        let pid: Int32
        let userID: UInt32
        let name: String
        let cpuPercent: Double
        let residentBytes: UInt64
        let executable: String
        let started: String
        let system: Bool
        let protected: Bool
        let receivedBytes: UInt64?
        let sentBytes: UInt64?
    }
    static func data(rows: [ProcessRow], traffic: [Int32: ProcessTraffic]) throws -> Data {
        let entries = rows.map { row in Entry(pid: row.id, userID: row.uid, name: row.name, cpuPercent: row.cpu, residentBytes: row.memory, executable: row.command, started: row.started, system: row.isSystem, protected: row.protected, receivedBytes: traffic[row.id]?.received, sentBytes: traffic[row.id]?.sent) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
}
