import Foundation

enum MenuMetric: String, CaseIterable {
    case cpu, gpu, memory, storage
    var label: String {
        switch self { case .cpu: return "CPU"; case .gpu: return "GPU"; case .memory: return "RAM"; case .storage: return "Disk" }
    }
    func value(in snapshot: SystemSnapshot) -> String {
        switch self {
        case .cpu: return snapshot.cpu.map { String(format: "%.0f%%", $0) } ?? "—"
        case .gpu: return snapshot.gpu.map { String(format: "%.0f%%", $0) } ?? "—"
        case .memory: return snapshot.usedRAM > 0 ? Self.compactBytes(snapshot.usedRAM) : "—"
        case .storage: return snapshot.diskTotal > 0 ? Self.compactBytes(snapshot.diskTotal - min(snapshot.diskFree, snapshot.diskTotal)) : "—"
        }
    }
    static func compactBytes(_ amount: UInt64) -> String {
        let gib = Double(amount) / 1_073_741_824
        if gib >= 100 { return String(format: "%.0f GB", gib) }
        if gib >= 1 { return String(format: "%.1f GB", gib) }
        return bytes(amount)
    }
    static func selected(_ selection: Set<MenuMetric>) -> [MenuMetric] { allCases.filter { selection.contains($0) } }
}
