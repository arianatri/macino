import Foundation

struct ProcessGroup: Identifiable {
    let id: String
    let bundlePath: String?
    let members: [ProcessRow]
    var name: String { bundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? members[0].name }
    var memory: UInt64 { members.reduce(0) { $0 + $1.memory } }
    var cpu: Double { members.reduce(0) { $0 + $1.cpu } }
    var isSystem: Bool { members.allSatisfy(\.isSystem) }
    func traffic(_ counters: [Int32: ProcessTraffic]) -> ProcessTraffic? {
        let visible = members.compactMap { counters[$0.id] }
        guard !visible.isEmpty else { return nil }
        return ProcessTraffic(received: visible.reduce(0) { $0 + $1.received }, sent: visible.reduce(0) { $0 + $1.sent })
    }
    func trafficCount(_ counters: [Int32: ProcessTraffic]) -> Int { members.filter { counters[$0.id] != nil }.count }
}

enum ProcessGrouping {
    static func identity(_ row: ProcessRow) -> (key: String, bundle: String?) {
        let path = URL(fileURLWithPath: row.command).standardizedFileURL.path
        // The OUTERMOST app owns nested helpers, renderers, frameworks and CLI tools.
        if let end = path.range(of: ".app/", options: .caseInsensitive)?.lowerBound {
            let bundle = String(path[..<end]) + String(path[end...].prefix(4))
            return ("app:" + bundle, bundle)
        }
        return ("executable:" + path, nil)
    }
    static func groups(_ rows: [ProcessRow], by sort: ProcessSort, descending: Bool, showSystem: Bool, search: String, traffic: [Int32: ProcessTraffic]) -> [ProcessGroup] {
        let eligible = rows.filter { showSystem || !$0.isSystem }
        let grouped = Dictionary(grouping: eligible) { identity($0).key }
        return grouped.map { key, members in
            ProcessGroup(id: key, bundlePath: identity(members[0]).bundle,
                         members: ProcessOrdering.rows(members, by: sort, descending: descending, showSystem: true, search: "", traffic: traffic))
        }.filter { group in
            search.isEmpty || group.name.localizedCaseInsensitiveContains(search) || group.members.contains { $0.name.localizedCaseInsensitiveContains(search) || String($0.id).contains(search) }
        }.sorted { a, b in
            switch sort {
            case .cpu: if a.cpu != b.cpu { return descending ? a.cpu > b.cpu : a.cpu < b.cpu }
            case .memory: if a.memory != b.memory { return descending ? a.memory > b.memory : a.memory < b.memory }
            case .system: if a.isSystem != b.isSystem { return descending ? a.isSystem : !a.isSystem }
            case .internet:
                let left = a.traffic(traffic)?.total, right = b.traffic(traffic)?.total
                if left == nil && right != nil { return false }
                if left != nil && right == nil { return true }
                if let left, let right, left != right { return descending ? left > right : left < right }
            }
            return a.id < b.id
        }
    }
}
