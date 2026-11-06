import AppKit
import SwiftUI

@MainActor final class InstallerDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var busy = false
    @Published var finished = false
    @Published var status = "Drag the macino icon into the heart to install."
    @Published var error: String?
    private var window: NSWindow!
    private var pending: URL?
    private var ready = false
    private var installed: URL?
    lazy var sourceIcon: NSImage = NSWorkspace.shared.icon(forFile: source.path)
    var source: URL { Bundle.main.resourceURL!.appendingPathComponent("macino.app") }
    var directory: URL {
        FileManager.default.isWritableFile(atPath: "/Applications") ? URL(fileURLWithPath: "/Applications") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 620,height: 520), styleMask: [.titled,.closable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Install with love"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: InstallerView(installer: self))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        ready = true
        if let pending { install(dropped: pending) }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first else { error = "Drop only the macino application included in this disk image."; return }
        if ready { install(dropped: url) } else { pending = url }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !busy }
    func install(dropped: URL? = nil) {
        guard !busy else { return }
        if let dropped, dropped.resolvingSymlinksInPath().standardizedFileURL != source.resolvingSymlinksInPath().standardizedFileURL { error = "Drop the macino.app included with this installer. Other applications are not accepted."; return }
        if finished, let installed { open(installed); return }
        let destination = directory.appendingPathComponent("macino.app")
        if FileManager.default.fileExists(atPath: destination.path) {
            let alert = NSAlert(); alert.messageText = "Update macino?"; alert.informativeText = "The running copy will quit. The existing application will be kept as a backup, then the new version will open. Your settings are preserved."
            alert.addButton(withTitle: "Update & open"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        busy = true; error = nil
        status = "Installing to \(directory.path)…"
        let source = source, directory = directory
        Task {
            do {
                let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.macino")
                for app in running where !app.isTerminated { guard app.terminate() else { throw InstallFailure("Quit macino before installing this update.") } }
                for _ in 0..<50 { if running.allSatisfy(\.isTerminated) { break }; try await Task.sleep(nanoseconds: 100_000_000) }
                guard running.allSatisfy(\.isTerminated) else { throw InstallFailure("macino is still running. Quit it and try again; no Force Quit was performed.") }
                let result = try await Task.detached(priority: .userInitiated) { try InstallTransaction.install(source: source, directory: directory) }.value
                installed = result.app; finished = true; status = "Installed successfully. Opening macino…"; open(result.app)
            } catch { self.error = error.localizedDescription; status = "Installation did not complete."; busy = false }
        }
    }
    private func open(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true; config.activates = true; config.arguments = ["--show", "--installer-pid", String(ProcessInfo.processInfo.processIdentifier)]
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            Task { @MainActor in
                self.busy = false
                if let error { self.error = "Installed, but macOS could not open macino: \(error.localizedDescription)" }
                else {
                    self.status = "macino is ready. Enjoy your calmer Mac."
                    self.window?.orderOut(nil)
                    exit(EXIT_SUCCESS)
                }
            }
        }
    }
}
struct InstallerView: View {
    @ObservedObject var installer: InstallerDelegate
    @State private var dropTargeted = false
    @State private var dragHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 9) {
                Text(installer.finished ? "Welcome home, macino." : "Install with love.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Created by Arian Atri")
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.teal)
                Text(installer.status).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 510)
            }.padding(.top, 16)
            Spacer(minLength: 12)
            HStack(spacing: 20) {
                VStack(spacing: 9) {
                    Image(nsImage: installer.sourceIcon)
                        .resizable().interpolation(.high).frame(width: 92, height: 92)
                    Text("Drag this icon").font(.system(size: 12, weight: .semibold))
                }
                .frame(width: 210, height: 150)
                .transaction { $0.animation = nil }
                .background {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.teal.opacity(dragHovered ? 0.14 : 0.04))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: dragHovered)
                }
                .contentShape(RoundedRectangle(cornerRadius: 28))
                .onHover { dragHovered = $0 }
                .onDrag { NSItemProvider(object: installer.source as NSURL) }
                .accessibilityLabel("macino application. Drag onto the heart to install")
                DragDirectionArrow(paused: installer.busy)
                VStack(spacing: 9) {
                Image(systemName: "heart.fill").font(.system(size: 64)).foregroundStyle(.pink.gradient)
                    .scaleEffect(dropTargeted && !reduceMotion ? 1.12 : 1)
                Text(dropTargeted ? "Release to install & open" : "Drop icon here")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }.frame(width: 210, height: 150)
                .background(.pink.opacity(dropTargeted ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 28))
                .contentShape(RoundedRectangle(cornerRadius: 28))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: dropTargeted)
                .onDrop(of: [.fileURL, .url], isTargeted: $dropTargeted) { providers in
                    guard providers.count == 1, !installer.busy,
                          let provider = providers.first,
                          provider.canLoadObject(ofClass: NSURL.self) else { return false }
                    _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                        guard let url = object as? URL else { return }
                        Task { @MainActor in installer.install(dropped: url) }
                    }
                    return true
                }
                .accessibilityLabel("Drop the macino application here to install and open it")
            }.frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            if installer.busy { ProgressView().controlSize(.small) }
            if let error = installer.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Button(installer.finished ? "Open macino" : "Install & open macino") { installer.install() }.buttonStyle(.borderedProminent).tint(.teal).disabled(installer.busy)
            Text("macino opens automatically after installation.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 620,height: 520).background(.ultraThinMaterial)
    }
}

private struct DragDirectionArrow: View {
    let paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || paused)) { timeline in
            let phase = reduceMotion || paused ? 0.5 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
            ZStack {
                Capsule().fill(.teal.opacity(0.12)).frame(width: 72, height: 3)
                Image(systemName: "arrow.right")
                    .font(.system(size: 25, weight: .semibold)).foregroundStyle(.teal)
                    .offset(x: -20 + 40 * phase)
                    .opacity(reduceMotion || paused ? 1 : 0.25 + 0.75 * sin(phase * .pi))
            }.frame(width: 82, height: 42)
        }.accessibilityLabel("Drag macino from left to right into the heart")
    }
}

@main enum InstallerApp {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.indices.contains(index + 1) {
            do { try InstallTransaction.selfTest(source: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
            catch { fputs("Installer test failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        let application = NSApplication.shared
        let delegate = InstallerDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
