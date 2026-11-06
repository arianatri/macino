import SwiftUI

struct InternetTrafficDrawer: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Network usage", systemImage: "network").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        InfoButton(title: "Network usage", text: "Visible nettop socket byte totals for each process. These are cumulative counters, not speed or internet permissions. Local traffic is included; visibility may be restricted and totals can reset when sockets close.")
                    }
                    if let error = model.trafficError { Text(error).font(.caption).foregroundStyle(.red) }
                    if model.traffic.isEmpty { Text("No visible network counters.").font(.caption).foregroundStyle(.secondary) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.traffic) { row in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.id).font(.system(size: 11, weight: .medium)).lineLimit(1).help(row.id)
                                    HStack {
                                        Text("↓ \(bytes(row.received))")
                                        Spacer()
                                        Text("↑ \(bytes(row.sent))")
                                    }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }.padding(14).frame(width: 300).frame(maxHeight: .infinity, alignment: .top)
                    .background(.regularMaterial)
    }
}

struct NetworkUsageHandle: View {
    @Binding var expanded: Bool
    var body: some View {
        Button { expanded.toggle() } label: {
            VStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Network usage").font(.system(size: 10, weight: .semibold))
                    .fixedSize().rotationEffect(.degrees(-90)).frame(width: 22, height: 100)
            }.foregroundStyle(.teal).frame(width: 30, height: 140)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.teal.opacity(0.25)))
        }.buttonStyle(.plain)
            .help(expanded ? "Close Network usage" : "Open Network usage to the left")
            .accessibilityLabel(expanded ? "Close Network usage" : "Open Network usage")
    }
}
