import SwiftUI
import AppKit
import Combine

@main enum MacinoApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var setupWindow: NSWindow?
    private var metricsSubscription: AnyCancellable?
    private var outsideMonitor: Any?
    private var menuIcon: NSImage!
    var item: NSStatusItem!; let panel = MenuPanel(); let model = AppModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let p = NSBezierPath(); p.move(to: NSPoint(x: 3,y: 6)); p.line(to: NSPoint(x: 3,y: 12)); p.curve(to: NSPoint(x: 11,y: 12), controlPoint1: NSPoint(x: 3,y: 18), controlPoint2: NSPoint(x: 11,y: 18)); p.line(to: NSPoint(x: 11,y: 6)); p.line(to: NSPoint(x: 11,y: 12)); p.curve(to: NSPoint(x: 19,y: 12), controlPoint1: NSPoint(x: 11,y: 18), controlPoint2: NSPoint(x: 19,y: 18)); p.line(to: NSPoint(x: 19,y: 6)); p.lineWidth = 2; p.lineCapStyle = .round; NSColor.black.setStroke(); p.stroke(); return true
        }; menuIcon = image; image.isTemplate = true; image.accessibilityDescription = "macino"
        item.button?.image = image; item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.toolTip = "macino • Your Mac, at a glance"
        panel.onDismiss = { [weak self] in self?.closePanel() }
        _ = ClipboardHistory.shared
        panel.contentViewController = GlassHostingController(rootView: MainView(model: model, showSetup: { [weak self] in self?.showSetup() }, resizeForNetwork: { [weak self] expanded in self?.panel.setNetworkExpanded(expanded) }, showAbout: { [weak self] in self?.showAbout() }, dialogStateChanged: { [weak self] visible in self?.panel.dialogIsVisible = visible }, readerStateChanged: { [weak self] selected in self?.panel.readerIsSelected = selected }), menuBubble: true)
        metricsSubscription = Publishers.CombineLatest(model.$system, model.$menuMetrics).sink { [weak self] snapshot, metrics in
            self?.updateMenuMetrics(snapshot, selection: metrics)
        }
        if CommandLine.arguments.contains("--reader-playback-test") {
            Task {
                do { try await ReaderPlaybackSelfTest.run(); exit(0) }
                catch { fputs("Reader playback test failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        if CommandLine.arguments.contains("--self-test") { do { try SelfTest.run() } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }; NSApp.terminate(nil) }
        if CommandLine.arguments.contains("--smoke-test") { Task { await model.refresh(); let s = model.system; print("SMOKE model=\(s.model) cpu=\(String(describing: s.cpu)) gpu=\(String(describing: s.gpu)) ram=\(s.usedRAM)/\(s.totalRAM) disk=\(s.diskFree)/\(s.diskTotal)"); do { print("SMOKE processes=\(try ProcessManager.sample().count) network=\(try NetworkActivity.sample().count) services=\(try NetworkSettings.services()) caches=\(try Cleanup.scan().count)") } catch { print("SMOKE ERROR \(error)") }; NSApp.terminate(nil) } }
        _ = ClipboardQuickPanel.shared
        model.reconcileMonitoring()
        if CommandLine.arguments.contains("--setup") || Bundle.main.bundlePath.hasPrefix("/Volumes/") || (SetupModel.isInstalled(Bundle.main.bundleURL) && (!UserDefaults.standard.bool(forKey: "setupComplete") || !UserDefaults.standard.bool(forKey: "loginPromptShown")) && !CommandLine.arguments.contains("--show")) {
            DispatchQueue.main.async { self.showSetup() }
        }
        if CommandLine.arguments.contains("--show") {
            Task { @MainActor in
                // Wait for the installer to exit before taking focus. Its shutdown can
                // otherwise deactivate this app and dismiss the freshly opened panel.
                let args = CommandLine.arguments
                if let index = args.firstIndex(of: "--installer-pid"), args.indices.contains(index + 1),
                   let pid = Int32(args[index + 1]) {
                    let installer = NSRunningApplication(processIdentifier: pid)
                    for _ in 0..<100 {
                        if installer?.isTerminated != false { break }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
                self.setupWindow?.close()
                if !self.panel.isVisible { self.toggle() }
                else if let button = self.item.button { self.panel.show(below: button) }
            }
        }
    }
    private func updateMenuMetrics(_ snapshot: SystemSnapshot, selection: Set<MenuMetric>) {
        guard let button = item.button else { return }
        let metrics = MenuMetric.selected(selection)
        item.length = metrics.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.image = MenuMetricsImage.make(icon: menuIcon, snapshot: snapshot, selection: selection)
        let summary = metrics.map { "\($0.label) \($0.value(in: snapshot))" }.joined(separator: ", ")
        button.setAccessibilityLabel(summary.isEmpty ? "macino" : "macino, " + summary)
        button.toolTip = summary.isEmpty ? "macino • Your Mac, at a glance" : "macino • " + summary + "\nRAM and storage show used capacity. — means sampling or unavailable."
    }
    func showAbout() { closePanel(); AboutMacino.present() }
    func showSetup() {
        closePanel()
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Welcome to macino"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isOpaque = false; window.backgroundColor = .clear; window.isReleasedWhenClosed = false
            window.contentViewController = GlassHostingController(rootView: SetupView { [weak self] in
                if SetupModel.isInstalled(Bundle.main.bundleURL) { UserDefaults.standard.set(true, forKey: "setupComplete") }; self?.setupWindow?.close()
            })
            window.center(); setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !panel.isVisible { toggle() }; return false }
    @objc func toggle() {
        if panel.isVisible { closePanel() }
        else if let button = item.button {
            panel.show(below: button); model.start()
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.closePanel(automatic: true) }
            }

        }
    }
    private func closePanel(automatic: Bool = false) {
        guard automatic ? panel.canDismissAutomatically : panel.canDismissExplicitly else { return }
        if !automatic && panel.readerIsSelected { ReaderModel.shared.stop() }
        panel.orderOut(nil); model.stop()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
    }
    func applicationWillTerminate(_ notification: Notification) { AndroidScreenSession.shared.stop(); ReaderModel.shared.closeDocument() }
    func applicationDidResignActive(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            if !NSApp.isActive { self?.closePanel(automatic: true) }
        }
    }
}
