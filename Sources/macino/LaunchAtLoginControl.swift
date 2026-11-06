import SwiftUI
import ServiceManagement

/// One shared login-item control for the System page and the full settings window.
struct LaunchAtLoginControl: View {
    @ObservedObject var setup: SetupModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { setup.loginRequested }, set: setup.setLogin)) {
                Label("Launch macino at login", systemImage: "power")
                    .font(.system(size: 12, weight: .medium))
            }.toggleStyle(.switch).controlSize(.small)
                .disabled(!setup.canConfigureLogin || setup.loginUpdating)
            if let saved = setup.localLoginPath, saved != Bundle.main.bundlePath {
                Button("Use this copy for login") { setup.setLogin(true) }.controlSize(.small)
            }
            if setup.loginUpdating { ProgressView().controlSize(.small) }
            if setup.loginStatus == .requiresApproval {
                Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }.controlSize(.small)
            }
        }
        .onAppear { setup.refreshLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in setup.refreshLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in setup.refreshLogin() }
    }
}
