import AppKit
import SwiftUI

@MainActor enum ProcessInfoWindow {
    private static var controller: NSWindowController?
    static func show(name: String, rows: [ProcessRow], traffic: [Int32: ProcessTraffic]) {
        controller?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 580), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Process Info — \(name)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProcessDetails(name: name, rows: rows, traffic: traffic, onClose: { [weak window] in window?.close() }))
        window.minSize = NSSize(width: 460, height: 360)
        let owner = NSWindowController(window: window)
        controller = owner
        window.center(); owner.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
private struct ProcessDetails: View {
    let name: String
    let rows: [ProcessRow]
    let traffic: [Int32: ProcessTraffic]
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.title2.bold())
            Text("\(rows.count) processes • Snapshot at opening").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(String(format: "CPU %.1f%%", rows.reduce(0) { $0 + $1.cpu }))
                Spacer()
                Text("RAM \(bytes(rows.reduce(UInt64(0)) { $0 + $1.memory }))")
            }.font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(rows) { row in
                        ProcessDetailCard(row: row, traffic: traffic[row.id])
                    }
                }
            }
            Text("CPU: lifetime average, 100% = one core. RAM: RSS; shared pages can appear in multiple processes.").font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Copy report") { report(copy: true) }
                Button("Export JSON…") { report(copy: false) }
                Spacer()
                Button(action: onClose) { Label("Close", systemImage: "xmark") }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(minWidth: 420, minHeight: 320)
    }
    private func report(copy: Bool) {
        do {
            let data = try ProcessReport.data(rows: rows, traffic: traffic)
            if copy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
            } else {
                let panel = NSSavePanel(); panel.nameFieldStringValue = "macino-processes.json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url, options: .atomic)
            }
        } catch { NSAlert(error: error).runModal() }
    }

}

private struct ProcessDetailCard: View {
    let row: ProcessRow
    let traffic: ProcessTraffic?
    @State private var diagnostic: ProcessDiagnostic?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(row.name).font(.headline)
            LabeledContent("PID / User ID", value: "\(row.id) / \(row.uid)")
            LabeledContent("Started", value: row.started)
            LabeledContent("CPU", value: String(format: "%.1f%%", row.cpu))
            LabeledContent("Resident RAM", value: bytes(row.memory))
            LabeledContent("System", value: row.isSystem ? "Yes" : "No")
            LabeledContent("Protected", value: row.protected ? "Yes" : "No")
            if let traffic { LabeledContent("Network counters", value: "↓ \(bytes(traffic.received))  ↑ \(bytes(traffic.sent))") }
            Text(row.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.command)])
                } label: { Label("Reveal", systemImage: "folder") }
                Button(loading ? "Reading…" : "Parent & Connections") { inspect() }.disabled(loading)
            }.controlSize(.small)
            if let diagnostic {
                Divider()
                LabeledContent("Parent", value: diagnostic.parent)
                LabeledContent("State / Elapsed", value: "\(diagnostic.state) / \(diagnostic.elapsed)")
                LabeledContent("Nice", value: diagnostic.priority)
                Text("Visible connections").font(.caption.bold())
                ScrollView(.horizontal) {
                    Text(diagnostic.connections).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.font(.callout).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
    private func inspect() {
        loading = true; error = nil
        Task {
            do { diagnostic = try await Task.detached(priority: .utility) { try ProcessDiagnostics.inspect(row) }.value }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
