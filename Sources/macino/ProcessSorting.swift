import Foundation

enum ProcessSort: String, CaseIterable {
    case cpu = "CPU", memory = "RAM", internet = "Internet", system = "System"
}

struct ProcessTraffic {
    let received: UInt64
    let sent: UInt64
    var total: UInt64 { received.addingReportingOverflow(sent).overflow ? UInt64.max : received + sent }

    static func indexed(_ rows: [TrafficRow]) -> [Int32: ProcessTraffic] {
        var result: [Int32: ProcessTraffic] = [:]
        for row in rows {
            guard let suffix = row.id.split(separator: ".").last, let pid = Int32(suffix) else { continue }
            result[pid] = ProcessTraffic(received: row.received, sent: row.sent)
        }
        return result
    }
}

enum ProcessOrdering {
    static func rows(_ rows: [ProcessRow], by sort: ProcessSort, descending: Bool, showSystem: Bool, search: String, traffic: [Int32: ProcessTraffic]) -> [ProcessRow] {
        rows.filter { (showSystem || !$0.isSystem) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.id).contains(search)) }
            .sorted { a, b in
                switch sort {
                case .cpu:
                    if a.cpu != b.cpu { return descending ? a.cpu > b.cpu : a.cpu < b.cpu }
                case .memory:
                    if a.memory != b.memory { return descending ? a.memory > b.memory : a.memory < b.memory }
                case .system:
                    if a.isSystem != b.isSystem { return descending ? a.isSystem : !a.isSystem }
                case .internet:
                    // Missing visibility is not a zero measurement; keep unavailable rows last in either direction.
                    let left = traffic[a.id]?.total, right = traffic[b.id]?.total
                    if left == nil && right != nil { return false }
                    if left != nil && right == nil { return true }
                    if let left, let right, left != right { return descending ? left > right : left < right }
                }
                return a.id < b.id
            }
    }
}
