import Foundation
import Network

struct ProxyConfig: Codable, Equatable {
    var kind: String; var enabled = false; var host = ""; var port = "8080"
    var title: String { ["web": "HTTP", "secureweb": "HTTPS", "socksfirewall": "SOCKS"][kind] ?? kind }
}
struct ServiceConfig: Codable { var service: String; var proxies: [ProxyConfig]; var dns: [String] }
enum NetworkSettings {
    static let backupURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/macino/network-backup.json")
    static func services() throws -> [String] { try Shell.checked("/usr/sbin/networksetup", ["-listallnetworkservices"]).components(separatedBy: "\n").dropFirst().filter { !$0.isEmpty && !$0.hasPrefix("*") } }
    static func read(_ service: String) throws -> ServiceConfig {
        var proxies: [ProxyConfig] = []
        for kind in ["web", "secureweb", "socksfirewall"] {
            let output = try Shell.checked("/usr/sbin/networksetup", ["-get\(kind)proxy", service])
            let lines = output.components(separatedBy: "\n")
            func field(_ name: String) -> String { lines.first(where: { $0.hasPrefix(name + ": ") }).map { String($0.dropFirst(name.count + 2)) } ?? "" }
            // Authenticated proxies cannot be round-tripped without retrieving credentials.
            if field("Authenticated Proxy Enabled") == "1" { throw AppError.message("This service uses an authenticated proxy. Manage it in System Settings to preserve credentials.") }
            proxies.append(ProxyConfig(kind: kind, enabled: field("Enabled") == "Yes", host: field("Server"), port: field("Port")))
        }
        let dns = try Shell.checked("/usr/sbin/networksetup", ["-getdnsservers", service])
        return ServiceConfig(service: service, proxies: proxies, dns: dns.contains("There aren't any DNS Servers") ? [] : dns.components(separatedBy: "\n"))
    }
    static func validate(_ config: ServiceConfig) throws {
        guard try services().contains(config.service) else { throw AppError.message("Select an available network service.") }
        for p in config.proxies where p.enabled || !p.host.isEmpty {
            guard !p.host.isEmpty, !p.host.contains(where: { $0.isWhitespace }), let port = Int(p.port), (1...65535).contains(port) else { throw AppError.message("Enter a proxy host and port between 1 and 65535.") }
        }
        for ip in config.dns { var v4 = in_addr(); var v6 = in6_addr(); guard inet_pton(AF_INET, ip, &v4) == 1 || inet_pton(AF_INET6, ip, &v6) == 1 else { throw AppError.message("DNS servers must be IPv4 or IPv6 addresses: \(ip)") } }
    }
    static func apply(_ config: ServiceConfig, restoring: Bool = false) throws -> ServiceConfig {
        try validate(config)
        let old = try read(config.service)
        if !restoring {
            try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var saved = (try? JSONDecoder().decode([String: ServiceConfig].self, from: Data(contentsOf: backupURL))) ?? [:]
            saved[config.service] = old
            try JSONEncoder().encode(saved).write(to: backupURL, options: .atomic)
        }
        var commands: [[String]] = []
        for p in config.proxies {
            if !p.host.isEmpty { commands.append(["/usr/sbin/networksetup", "-set\(p.kind)proxy", config.service, p.host, p.port]) }
            commands.append(["/usr/sbin/networksetup", "-set\(p.kind)proxystate", config.service, p.enabled ? "on" : "off"])
        }
        commands.append(["/usr/sbin/networksetup", "-setdnsservers", config.service] + (config.dns.isEmpty ? ["Empty"] : config.dns))
        try Shell.admin(commands)
        let verified = try read(config.service)
        guard verified.dns == config.dns, zip(verified.proxies, config.proxies).allSatisfy({ a, b in a.enabled == b.enabled && (b.host.isEmpty || (a.host == b.host && a.port == b.port)) }) else { throw AppError.message("Read-back differs from requested settings. Refresh and inspect; the previous configuration is available using Restore.") }
        return verified
    }
    static func defaultProxyKinds(_ kind: String?) throws -> [String] {
        let kinds = ["web", "secureweb", "socksfirewall"]
        guard let kind else { return kinds }
        guard kinds.contains(kind) else { throw AppError.message("Unknown proxy type.") }
        return [kind]
    }
    static func proxyDefaultCommands(_ service: String, kind: String? = nil) throws -> [[String]] {
        try defaultProxyKinds(kind).map { ["/usr/sbin/networksetup", "-set\($0)proxystate", service, "off"] }
    }
    /// Defaults means direct connections: disable only the requested proxy states.
    /// DNS, other proxy types and saved server addresses remain unchanged.
    static func restoreProxyDefaults(_ service: String, kind: String? = nil) throws -> ServiceConfig {
        let kinds = try defaultProxyKinds(kind)
        guard try services().contains(service) else { throw AppError.message("Select an available network service.") }
        let previous = try read(service)
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backups = (try? JSONDecoder().decode([String: ServiceConfig].self, from: Data(contentsOf: backupURL))) ?? [:]
        backups[service] = previous
        try JSONEncoder().encode(backups).write(to: backupURL, options: .atomic)
        try Shell.admin(proxyDefaultCommands(service, kind: kind))
        let verified = try read(service)
        guard verified.dns == previous.dns, zip(verified.proxies, previous.proxies).allSatisfy({ current, old in
            current.host == old.host && current.port == old.port && current.enabled == (kinds.contains(old.kind) ? false : old.enabled)
        }) else { throw AppError.message("Proxy reset read-back differed. Refresh to inspect; the previous settings were backed up.") }
        return verified
    }
    static func restore(_ service: String) throws -> ServiceConfig {
        let saved = try JSONDecoder().decode([String: ServiceConfig].self, from: Data(contentsOf: backupURL))
        guard let config = saved[service] else { throw AppError.message("No saved configuration for this service.") }
        return try apply(config, restoring: true)
    }
}
struct TerminalProxy: Codable {
    var http = ""; var https = ""; var all = ""; var bypass = "localhost,127.0.0.1,::1"; var enabled = false
    static let begin = "# >>> macino proxy >>>", end = "# <<< macino proxy <<<"
    static var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc") }
    static var stateFile: URL { NetworkSettings.backupURL.deletingLastPathComponent().appendingPathComponent("terminal.json") }
    static func load() -> Self { (try? JSONDecoder().decode(Self.self, from: Data(contentsOf: stateFile))) ?? Self() }
    var command: String {
        if !enabled { return "unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY" }
        return "unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY\n" + [("http_proxy", http), ("https_proxy", https), ("all_proxy", all), ("no_proxy", bypass)].map { "export \($0.0)=\(Shell.quote($0.1))" }.joined(separator: "\n")
    }
    func save(to file: URL = Self.file, stateURL: URL = Self.stateFile, recordBackup: Bool = true) throws -> String {
        for value in [http, https, all] where !value.isEmpty {
            guard let u = URLComponents(string: value), let scheme = u.scheme, ["http", "https", "socks5", "socks5h"].contains(scheme), u.host != nil, let port = u.port, (1...65535).contains(port), u.user == nil, u.password == nil else { throw AppError.message("Use a proxy URL such as http://127.0.0.1:8080 or socks5://127.0.0.1:1080, without credentials.") }
        }
        let fm = FileManager.default
        if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw AppError.message(".zshrc is a symbolic link; edit its target manually using the copyable command.") }
        let old = fm.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : ""
        var content = old
        if let start = content.range(of: Self.begin) { guard let end = content.range(of: Self.end), end.lowerBound > start.lowerBound else { throw AppError.message("Incomplete macino block in .zshrc. Repair it before saving.") }; content.removeSubrange(start.lowerBound..<end.upperBound) }
        let backup = file.appendingPathExtension("macino-backup-\(UUID().uuidString)")
        try old.write(to: backup, atomically: true, encoding: .utf8)
        content += "\n\(Self.begin)\n\(command)\n\(Self.end)\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
        try fm.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: stateURL, options: .atomic)
        if recordBackup { UserDefaults.standard.set(backup.path, forKey: "shellBackup") }
        return "Saved to ~/.zshrc. Open a new zsh terminal or copy the command. Backup: \(backup.lastPathComponent)"
    }
    @discardableResult static func restoreDefaults(to file: URL = Self.file, stateURL: URL = Self.stateFile, recordBackup: Bool = true) throws -> Self {
        let defaults = Self()
        _ = try defaults.save(to: file, stateURL: stateURL, recordBackup: recordBackup)
        return defaults
    }
    static func restore() throws { guard let path = UserDefaults.standard.string(forKey: "shellBackup") else { throw AppError.message("No shell backup available.") }; let original = try String(contentsOfFile: path, encoding: .utf8); let current = try String(contentsOf: file, encoding: .utf8); try current.write(to: file.appendingPathExtension("before-restore-\(UUID().uuidString)"), atomically: true, encoding: .utf8); try original.write(to: file, atomically: true, encoding: .utf8) }
}
struct TrafficRow: Identifiable { var id: String; var received: UInt64; var sent: UInt64 }
enum NetworkActivity {
    static func sample() throws -> [TrafficRow] {
        let output = try Shell.checked("/usr/bin/nettop", ["-L", "1", "-P", "-n", "-x", "-J", "bytes_in,bytes_out"])
        return output.components(separatedBy: "\n").compactMap { line in let parts = line.components(separatedBy: ","); guard parts.count >= 3, let received = UInt64(parts[1]), let sent = UInt64(parts[2]), !parts[0].isEmpty else { return nil }; return TrafficRow(id: parts[0], received: received, sent: sent) }.sorted { $0.received + $0.sent > $1.received + $1.sent }
    }
}
