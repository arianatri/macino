import SwiftUI
import Charts
import AppKit

struct ResourcePoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double?
    let gpu: Double?
    let memory: Double
    let temperature: Double?
}
struct ResourceHistory {
    private(set) var points: [ResourcePoint] = []
    mutating func append(_ snapshot: SystemSnapshot, at date: Date = Date()) {
        points.append(ResourcePoint(date: date, cpu: snapshot.cpu, gpu: snapshot.gpu,
                                    memory: snapshot.totalRAM > 0 ? 100 * Double(snapshot.usedRAM) / Double(snapshot.totalRAM) : 0,
                                    temperature: snapshot.cpuTemperature))
        if points.count > 120 { points.removeFirst(points.count - 120) }
    }
}
@MainActor final class ResourceWindow: NSObject, NSWindowDelegate {
    private static let shared = ResourceWindow()
    private var controller: NSWindowController?
    private weak var model: AppModel?
    static func show(_ model: AppModel) {
        let owner = shared
        if let window = owner.controller?.window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Resource History"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 500)
        window.contentView = NSHostingView(rootView: ResourceDetails(model: model, onClose: { [weak window] in window?.close() }))
        owner.model = model; owner.controller = NSWindowController(window: window); window.delegate = owner
        model.historyVisible = true; model.reconcileMonitoring()
        window.center(); owner.controller?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        model?.historyVisible = false; model?.reconcileMonitoring()
    }
}
private struct ResourceDetails: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Resource History").font(.title2.bold()); Spacer(); Text("Live • 3 s").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Label("Memory pressure: " + model.system.memoryPressure, systemImage: "memorychip")
                Spacer()
                Text("Uptime \(Int(model.system.uptime / 3600))h \(Int(model.system.uptime / 60) % 60)m")
            }.font(.callout)
            HStack {
                metric("Wired", model.system.wiredRAM)
                metric("Compressed", model.system.compressedRAM)
                metric("Swap used", model.system.swapUsed)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    historyChart("CPU / GPU / Memory", temperature: false)
                    if model.history.points.contains(where: { $0.temperature != nil }) {
                        historyChart("CPU temperature · °C", temperature: true)
                    }
                    Text("Up to 120 samples in memory. Gaps use actual sample times; history is collected only while monitoring is active.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            HStack {
                Button("Export CSV…", action: export)
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.cancelAction).buttonStyle(.borderedProminent).tint(.teal)
            }
        }.padding(20)
    }
    private func metric(_ title: String, _ value: UInt64?) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value.map(bytes) ?? "Unavailable").font(.headline) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func historyChart(_ title: String, temperature: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(model.history.points) { point in
                if temperature {
                    if let value = point.temperature { LineMark(x: .value("Time", point.date), y: .value("°C", value)).foregroundStyle(.orange) }
                } else {
                    if let value = point.cpu { LineMark(x: .value("Time", point.date), y: .value("%", value)).foregroundStyle(by: .value("Resource", "CPU")) }
                    if let value = point.gpu { LineMark(x: .value("Time", point.date), y: .value("%", value)).foregroundStyle(by: .value("Resource", "GPU")) }
                    LineMark(x: .value("Time", point.date), y: .value("%", point.memory)).foregroundStyle(by: .value("Resource", "Memory"))
                }
            }.chartYScale(domain: temperature ? 0...120 : 0...100).frame(height: 175)
        }
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "macino-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatter = ISO8601DateFormatter()
        let lines = model.history.points.map { point in
            [formatter.string(from: point.date), point.cpu.map { String($0) } ?? "", point.gpu.map { String($0) } ?? "", String(point.memory), point.temperature.map { String($0) } ?? ""].joined(separator: ",")
        }
        do { try ("time,cpu_percent,gpu_percent,memory_percent,cpu_celsius\n" + lines.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8) }
        catch { let alert = NSAlert(error: error); alert.runModal() }
    }
}

struct ResourceHistoryButton: View {
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            Label("History", systemImage: "chart.xyaxis.line")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovered ? Color.teal : Color.secondary)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(hovered ? Color.teal.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hovered ? Color.teal.opacity(0.8) : Color.secondary.opacity(0.3), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hovered)
            .help("Open resource history, memory pressure and swap")
            .accessibilityLabel("Open resource history")
    }
}
