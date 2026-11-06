import SwiftUI

struct MemoryUsageBar: View {
    let used: UInt64
    let total: UInt64
    private var ratio: Double { total > 0 ? Double(used) / Double(total) : 0 }
    private var percentage: String {
        guard total > 0 else { return "Unavailable" }
        if used > 0 && ratio < 0.001 { return "<0.1%" }
        return String(format: "%.1f%%", ratio * 100)
    }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("RAM · \(bytes(used))")
                Spacer()
                Text(percentage).monospacedDigit()
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                Capsule().fill(.teal.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [.teal.opacity(0.6), .teal], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * min(max(ratio, 0), 1))
                    }
            }.frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resident memory \(bytes(used)), \(percentage) of installed RAM")
        .help("Resident size divided by \(bytes(total)) installed RAM. Shared pages can be counted more than once, especially in groups.")
    }
}
