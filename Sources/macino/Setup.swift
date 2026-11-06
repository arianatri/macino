import AppKit
import SwiftUI
import ServiceManagement

struct AccessCheck: Identifiable {
    let id: String
    let available: Bool
    let detail: String
}

@MainActor final class SetupModel: ObservableObject {
    private let localBuild = LocalLoginAgent.isAdHoc(Bundle.main.bundleURL)
    @Published var localLoginPath: String?
    @Published var loginUpdating = false
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var checks: [AccessCheck] = []
    @Published var checking = false
    @Published var message: String?
    @Published var folderStatus = "Choose a folder to see if macino can open it. This only checks the folder you choose."
    @Published var authorizationStatus = "macOS may ask for your password when you change network settings or flush DNS."
    @Published var authorizing = false
    var installed: Bool { Self.isInstalled(Bundle.main.bundleURL) }
    static func isInstalled(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    var canConfigureLogin: Bool { !Bundle.main.bundlePath.hasPrefix("/Volumes/") && (installed || localBuild) }
    var loginRequested: Bool { localLoginPath != nil || loginStatus == .enabled || loginStatus == .requiresApproval }
    var loginDescription: String {
        if localLoginPath != nil { return "Set to open when you log in. macOS may ask you to approve it in Login Items." }
        switch loginStatus {
        case .enabled: return "Enabled — macOS will launch macino when you sign in."
        case .notRegistered: return "Off — open macino yourself when you need it."
        case .requiresApproval: return "Approve macino in Login Items to finish."
        case .notFound: return localBuild ? "Off — turn on the switch to open macino when you log in." : "Launch at login isn’t set up for this copy yet."
        @unknown default: return "Couldn’t check launch at login. Try again."
        }
    }
    func refreshLogin() {
        loginStatus = SMAppService.mainApp.status
        do { localLoginPath = try LocalLoginAgent.savedApp() }
        catch { localLoginPath = nil; message = error.localizedDescription }
    }
    func setLogin(_ enabled: Bool) {
        guard canConfigureLogin else { message = "Install macino in Applications first, then turn on launch at login."; return }
        guard !loginUpdating else { return }; loginUpdating = true
        Task {
            defer { loginUpdating = false }
            do {
                if enabled {
                    if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                    else if loginStatus == .enabled { /* Already registered by macOS. */ }
                    else if localBuild { try LocalLoginAgent.save(app: Bundle.main.bundleURL) }
                    else {
                        try SMAppService.mainApp.register()
                        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try LocalLoginAgent.remove() }
                    }
                } else {
                    if loginStatus == .enabled || loginStatus == .requiresApproval { try await SMAppService.mainApp.unregister() }
                    try LocalLoginAgent.remove()
                }
            }
            catch { message = "macOS could not update the login item: \(error.localizedDescription). You can also add macino manually in Open Login Items." }
            refreshLogin()
        }
    }
    func checkAccess() {
        guard !checking else { return }; checking = true
        Task {
            checks = await Task.detached(priority: .utility) {
                var result: [AccessCheck] = []
                let system = SystemSampler().sample()
                result.append(AccessCheck(id: "System monitoring", available: system.totalRAM > 0 && system.diskTotal > 0, detail: "System stats are available. No extra permission needed."))
                do { let rows = try ProcessManager.sample(); result.append(AccessCheck(id: "Processes", available: !rows.isEmpty, detail: "\(rows.count) visible processes. You can stop processes that your account is allowed to manage.")) }
                catch { result.append(AccessCheck(id: "Processes", available: false, detail: error.localizedDescription)) }
                do { let rows = try NetworkActivity.sample(); result.append(AccessCheck(id: "Network counters", available: true, detail: "Available: \(rows.count) process network counters. Some protected processes may not appear.")) }
                catch { result.append(AccessCheck(id: "Network counters", available: false, detail: error.localizedDescription)) }
                return result
            }.value
            refreshLogin(); checking = false
        }
    }
    func chooseFolder() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        picker.message = "Choose a folder to check if macino can open it."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do { _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil); folderStatus = "Readable: \(url.path)" }
        catch { folderStatus = "Couldn’t open this folder: \(error.localizedDescription)" }
    }
    func openInstalledCopy() {
        let locations = [URL(fileURLWithPath: "/Applications/macino.app"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/macino.app")]
        guard let url = locations.first(where: { Bundle(url: $0)?.bundleIdentifier == "local.macino" }) else {
            message = "Drag macino into Applications first."; return
        }
        let config = NSWorkspace.OpenConfiguration(); config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            Task { @MainActor in
                if let error { self.message = error.localizedDescription }
                else { NSApp.terminate(nil) }
            }
        }
    }
    func verifyAuthorization() {
        guard !authorizing else { return }; authorizing = true
        Task {
            do {
                try await Task.detached { try Shell.admin([["/usr/bin/true"]]) }.value
                authorizationStatus = "Permission confirmed at \(Date().formatted(date: .omitted, time: .shortened)). macOS may ask again next time."
            } catch { authorizationStatus = "Permission wasn’t granted: \(error.localizedDescription)" }
            authorizing = false
        }
    }
}

struct SetupView: View {
    @StateObject private var setup = SetupModel()
    @State private var askLogin = false
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Settings").font(.system(size: 27, weight: .bold, design: .rounded))
                }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 20)
            .alert("Start macino when you log in?", isPresented: $askLogin) {
                Button("Turn on") {
                    UserDefaults.standard.set(true, forKey: "loginPromptShown")
                    setup.setLogin(true)
                }
                Button("Not now", role: .cancel) {
                    UserDefaults.standard.set(true, forKey: "loginPromptShown")
                }
            } message: {
                Text("macino will open in your menu bar when you log in. You can turn this off anytime.")
            }
            ScrollView {
                VStack(spacing: 14) {
                    AppearanceSettings()
                    if !setup.installed {
                        Card(title: "Install macino") {
                            HStack(spacing: 14) {
                                Image(systemName: "heart.fill").font(.system(size: 36)).foregroundStyle(.pink)
                                Text("Drag macino into Applications, then open it from there.").font(.callout)
                            }
                            Text("Current app: \(Bundle.main.bundlePath)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack { Button("Open installed macino") { setup.openInstalledCopy() }; Button("Open Applications") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) } }
                        }
                    }
                    Card(title: "Launch at login") {
                        LaunchAtLoginControl(setup: setup)
                        HStack {
                            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            Button("Check status") { setup.refreshLogin() }
                        }.controlSize(.small)
                    }
                    Card(title: "Permissions") {
                        ForEach(setup.checks) { check in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: check.available ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(check.available ? .teal : .orange)
                                VStack(alignment: .leading, spacing: 3) { Text(check.id).font(.system(size: 12, weight: .semibold)); Text(check.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        HStack { Button("Check access") { setup.checkAccess() }.disabled(setup.checking); if setup.checking { ProgressView().controlSize(.small) } }
                        Text("Basic monitoring needs no extra permissions. The Fn + V clipboard shortcut needs Accessibility access; you can enable it in the Clipboard tab.").font(.caption2).foregroundStyle(.secondary)
                        Divider()
                        Label("Folders", systemImage: "folder").font(.headline)
                        Text(setup.folderStatus).font(.caption).foregroundStyle(.secondary)
                        Button("Choose a folder…") { setup.chooseFolder() }.controlSize(.small)
                        Divider()
                        Label("Administrator authorization", systemImage: "lock.shield").font(.headline)
                        Text(setup.authorizationStatus).font(.caption).foregroundStyle(.secondary)
                        Button(setup.authorizing ? "Waiting for macOS…" : "Check permission…") { setup.verifyAuthorization() }.disabled(setup.authorizing).controlSize(.small)
                        Text("This check won’t change any settings. macOS may ask again next time.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Card(title: "About us") {
                        LabeledContent("Created by", value: AboutMacino.author)
                            .font(.callout).tint(.teal)
                        Link(AboutMacino.profileLabel, destination: AboutMacino.profile).font(.callout).tint(.teal)
                    }
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                        Card(title: "Appearance") { Text("Reduce Transparency is on in macOS, so backgrounds will look less transparent.").font(.caption) }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 20)
            }
            HStack { Text("You can change these anytime.").font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Done", action: onDone).buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(width: 600, height: 700)
        .task {
            setup.refreshLogin()
            setup.checkAccess()
            if setup.installed && !UserDefaults.standard.bool(forKey: "loginPromptShown") {
                if setup.loginRequested { UserDefaults.standard.set(true, forKey: "loginPromptShown") }
                else { askLogin = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setup.refreshLogin() }
        .alert("macino", isPresented: Binding(get: { setup.message != nil }, set: { if !$0 { setup.message = nil } })) { Button("OK") { setup.message = nil } } message: { Text(setup.message ?? "") }
    }
}
