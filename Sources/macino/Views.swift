import SwiftUI
import AppKit

struct Card<Content: View>: View {
    let title: String
    var info: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                if let info { InfoButton(title: title, text: info) }
            }
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background {
                if #available(macOS 26.0, *) { RoundedRectangle(cornerRadius: 18).fill(.primary.opacity(0.035)) }
                else { RoundedRectangle(cornerRadius: 18).fill(.regularMaterial) }
            }
    }
}
struct InfoButton: View {
    let title: String
    let text: String
    @State private var presented = false
    @State private var buttonHovered = false
    @State private var popoverHovered = false
    @State private var pinned = false
    @State private var pending: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button {
            pending?.cancel()
            pinned.toggle(); presented = pinned
        } label: {
            Image(systemName: "info.circle").font(.system(size: 13))
                .foregroundStyle(buttonHovered || presented ? Color.teal : Color.secondary)
                .frame(width: 20, height: 20)
                .background(buttonHovered || presented ? Color.teal.opacity(0.12) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: buttonHovered)
        .accessibilityLabel("About " + title)
        .onHover { buttonHovered = $0; updateHover() }
        .popover(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(text).font(.callout).textSelection(.enabled)
                HStack { Spacer(); Button("Close") { pinned = false; presented = false }.keyboardShortcut(.cancelAction) }
            }.padding(16).frame(width: 320)
                .onHover { popoverHovered = $0; updateHover() }
                .onDisappear { popoverHovered = false }
        }
        .onChange(of: presented) { _, visible in
            if !visible { pinned = false; pending?.cancel() }
        }
        .onDisappear { pending?.cancel() }
    }
    private func updateHover() {
        pending?.cancel()
        if buttonHovered || popoverHovered {
            guard !presented else { return }
            pending = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                if buttonHovered || popoverHovered { presented = true }
            }
        } else if !pinned {
            // Allow crossing the small gap from the button to the popover.
            pending = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
                if !buttonHovered && !popoverHovered && !pinned { presented = false }
            }
        }
    }
}

struct UprightGauge: View {
    let label: String; let value: Double?; let display: String; let detail: String; let color: Color
    @Binding var showInMenuBar: Bool
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().trim(from: 0.12, to: 0.88).stroke(color.opacity(0.13), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(90))
                Circle().trim(from: 0.12, to: 0.12 + 0.76 * min(max((value ?? 0)/100,0),1)).stroke(AngularGradient(colors: [color.opacity(0.5), color], center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(90)).animation(.easeInOut(duration: 0.6), value: value)
                VStack(spacing: 4) { Text(display).font(.system(size: 24, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5); HStack(spacing: 5) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Toggle("Show \(label) in menu bar", isOn: $showInMenuBar).labelsHidden().toggleStyle(.checkbox).controlSize(.mini)
                        .help("Show \(label) next to the macino icon in the menu bar")
                } }.padding(12)
            }.frame(width: 120, height: 120)
            Text(detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 28)
        }.frame(maxWidth: .infinity)
    }
}
struct MainView: View {
    @ObservedObject var model: AppModel
    var showSetup: () -> Void = {}
    var resizeForNetwork: (Bool) -> Void = { _ in }
    var showAbout: () -> Void = {}
    var dialogStateChanged: (Bool) -> Void = { _ in }
    var readerStateChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var screenSession = AndroidScreenSession.shared
    @StateObject private var folders = FolderStore()
    @StateObject private var startup = SetupModel()
    @StateObject private var android = AndroidModel()
    @StateObject private var reader = ReaderModel.shared
    @State private var groupForce = false
    @State private var groupTarget: ProcessGroup?
    @State private var forceTarget: ProcessRow?
    @State private var search = ""
    @AppStorage("groupProcesses") private var groupProcesses = true
    @State private var expandedGroups: Set<String> = []
    @AppStorage("showSystemProcesses") private var showSystemProcesses = false
    @AppStorage("processSortDescending") private var processSortDescending = true
    @State private var terminal = TerminalProxy.load()
    @State private var restoreShell = false
    @State private var proxyResetTarget: String?
    @State private var proxyResetService = ""
    var body: some View {
        HStack(spacing: 0) {
            if model.tab == "Internet" && model.networkUsageExpanded {
                InternetTrafficDrawer(model: model).frame(width: MenuPanel.networkWidth, height: 650)
            }
            mainContent
        }
        .disabled(activeDialog != nil)
        .overlay { if let dialog = activeDialog { InAppDialogView(dialog: dialog) } }
        .onAppear { dialogStateChanged(activeDialog != nil); readerStateChanged(model.tab == "Reader") }
        .onReceive(NotificationCenter.default.publisher(for: .macinoCancelDialog)) { _ in activeDialog?.dismiss() }
        .onChange(of: activeDialog != nil) { _, visible in dialogStateChanged(visible) }
        .onChange(of: model.networkUsageExpanded) { _, expanded in resizeForNetwork(expanded && model.tab == "Internet") }
        .onChange(of: model.tab) { old, tab in
            readerStateChanged(tab == "Reader")
            if old == "Reader" && tab != "Reader" { reader.stop() }
            if tab != "Internet" { model.networkUsageExpanded = false; resizeForNetwork(false) }
        }
    }
    var mainContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.title2).foregroundStyle(.teal).frame(width: 38, height: 38).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) { Text("macino").font(.system(size: 22, weight: .bold, design: .rounded)); Text("A little clarity for your Mac").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button(action: showSetup) { Label("Settings", systemImage: "gearshape") }
                    .buttonStyle(.borderless).font(.system(size: 12)).help("Settings, launch at login and permissions")
                Menu { Button("About macino…", action: showAbout); Button("Settings…", action: showSetup); Divider(); Button("Refresh") { Task { await model.refresh() } }; Divider(); Button("Quit macino") { NSApp.terminate(nil) } } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).fixedSize()
            }.padding(20)
            AnimatedTabs(selection: $model.tab).padding(.horizontal,20).padding(.bottom, 14)
            Divider().opacity(0.5)
            ScrollView {
                VStack(spacing: 14) {
                    switch model.tab {
                    case "System": systemView
                    case "Processes": processesView
                    case "Quick Access": foldersView
                    case "TV": TVMirrorView()
                    case "Android": AndroidView(model: android)
                    case "Reader": ReaderView(reader: reader)
                    case "Clipboard": ClipboardHistoryView(history: ClipboardHistory.shared)
                    default: internetView
                    }
                }.padding(18).padding(.leading, model.tab == "Internet" ? 30 : 0)
            }
            .overlay(alignment: .leading) {
                if model.tab == "Internet" { NetworkUsageHandle(expanded: $model.networkUsageExpanded) }
            }
            HStack { Circle().fill(.teal).frame(width: 5,height: 5); Text(model.menuMetrics.isEmpty ? "Updates every 3 seconds" : "Menu bar stats are live"); Spacer(); Text("by Arian Atri").fontWeight(.semibold).foregroundStyle(.secondary) }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal,20).padding(.vertical,10)
        }.frame(width: MenuPanel.contentWidth, height: 650)
        .onChange(of: model.tab) { _, tab in Task { await model.refresh() }; if tab == "Internet", model.config == nil { model.loadNetwork() } }
    }
    private var activeDialog: InAppDialog? {
        if let message = model.message { return InAppDialog(title: "macino", message: message) { model.message = nil } }
        if let message = folders.error { return InAppDialog(title: "Quick Access", message: message) { folders.error = nil } }
        if let message = startup.message { return InAppDialog(title: "Launch at login", message: message) { startup.message = nil } }
        if let message = reader.message { return InAppDialog(title: "Offline Reader", message: message) { reader.message = nil } }
        if let message = android.message { return InAppDialog(title: "Android", message: message) { android.message = nil } }
        if let message = screenSession.message { return InAppDialog(title: "Android screen", message: message) { screenSession.message = nil } }
        if let target = proxyResetTarget {
            return InAppDialog(title: "Restore Defaults?", message: target == "terminal" ? "Disable macino’s terminal proxies? Your shell configuration will be backed up. Existing terminals need a new session or the copied command." : "Disable \(target == "all" ? "all proxies" : "this proxy") on \(proxyResetService)? DNS is unchanged. macOS may request authorization.", primaryTitle: "Restore Defaults", destructive: true, cancel: { proxyResetTarget = nil }) { confirmProxyReset(target) }
        }
        if let group = groupTarget {
            let force = groupForce
            return InAppDialog(title: "\(force ? "Force Kill" : "Kill") \(group.name)?", message: "All listed processes in this group will receive a termination request. Unsaved work may be lost.", primaryTitle: force ? "Force Kill group" : "Kill group", destructive: true, cancel: { groupTarget = nil }) {
                groupTarget = nil
                model.terminateGroup(group, force: force)
            }
        }
        if let row = forceTarget {
            return InAppDialog(title: "Force Kill \(row.name)?", message: "Unsaved work may be lost.", primaryTitle: "Force Kill", destructive: true, cancel: { forceTarget = nil }) {
                forceTarget = nil
                model.terminate(row, force: true)
            }
        }
        if restoreShell {
            return InAppDialog(title: "Restore the previous .zshrc file?", message: "This reverts all edits since the backup. The current file will also be backed up.", primaryTitle: "Restore shell file", destructive: true, cancel: { restoreShell = false }) {
                restoreShell = false
                do { try TerminalProxy.restore(); terminal = TerminalProxy.load(); model.message = "Restored shell backup. Open a new terminal. Saved editor values may differ from the restored file." }
                catch { model.message = error.localizedDescription }
            }
        }
        return nil
    }

    private func confirmProxyReset(_ target: String) {
        proxyResetTarget = nil
        if target == "terminal" {
            do { terminal = try TerminalProxy.restoreDefaults(); model.message = "Terminal proxy defaults restored. Open a new terminal, or copy the current-session command." }
            catch { model.message = error.localizedDescription }
        } else {
            model.restoreProxyDefaults(service: proxyResetService, kind: target == "all" ? nil : target)
        }
    }
    var systemView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "laptopcomputer").font(.system(size: 16)).foregroundStyle(.teal)
                Text(model.system.chip).font(.system(size: 12, weight: .semibold))
                Text("\(bytes(model.system.totalRAM)) RAM").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ResourceHistoryButton { ResourceWindow.show(model) }
                if let temperature = model.system.cpuTemperature {
                    Label(String(format: "%.1f °C", temperature), systemImage: "thermometer.medium")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                        .help("CPU sensor average • Thermal pressure: \(model.system.thermal)")
                        .accessibilityLabel("CPU temperature")
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .help("\(model.system.model) • \(ProcessInfo.processInfo.operatingSystemVersionString)")
            Card(title: "Live resources") {
                HStack { UprightGauge(label: "CPU", value: model.system.cpu, display: model.system.cpu.map { String(format: "%.0f%%", $0) } ?? "Sampling", detail: "All cores • interval load", color: .teal, showInMenuBar: menuBinding(.cpu)); UprightGauge(label: "GPU", value: model.system.gpu, display: model.system.gpu.map { String(format: "%.0f%%", $0) } ?? "Unavailable", detail: model.system.gpu == nil ? "No driver utilization counter" : "Driver device utilization", color: .indigo, showInMenuBar: menuBinding(.gpu)) }
                HStack { UprightGauge(label: "Memory", value: Double(model.system.usedRAM) / Double(model.system.totalRAM) * 100, display: bytes(model.system.usedRAM), detail: "of \(bytes(model.system.totalRAM)) • VM used, excluding file cache", color: .orange, showInMenuBar: menuBinding(.memory)); UprightGauge(label: "Storage", value: model.system.diskTotal > 0 ? Double(model.system.diskTotal - model.system.diskFree) / Double(model.system.diskTotal) * 100 : nil, display: bytes(model.system.diskTotal - model.system.diskFree), detail: "of \(bytes(model.system.diskTotal)) • \(bytes(model.system.diskFree)) free", color: .blue, showInMenuBar: menuBinding(.storage)) }
            }
            LaunchAtLoginControl(setup: startup).padding(.horizontal, 4)

        }
    }
    var processesView: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search apps or processes", text: $search).textFieldStyle(.roundedBorder)
                Button { model.processesPaused.toggle(); if !model.processesPaused { Task { await model.refresh() } } } label: {
                    Image(systemName: model.processesPaused ? "play.fill" : "pause.fill")
                }.help(model.processesPaused ? "Resume process updates" : "Pause process updates")
                    .accessibilityLabel(model.processesPaused ? "Resume process updates" : "Pause process updates")
            }
            HStack(spacing: 10) {
                Picker("Sort", selection: $model.processSort) {
                    ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(maxWidth: 150)
                Button { processSortDescending.toggle() } label: {
                    Image(systemName: processSortDescending ? "arrow.down" : "arrow.up")
                }.help(processSortDescending ? "Descending — click for ascending" : "Ascending — click for descending")
                    .accessibilityLabel(processSortDescending ? "Sort descending" : "Sort ascending")
                Spacer(minLength: 0)
                Toggle("Group", isOn: $groupProcesses).toggleStyle(.checkbox)
                    .help("Group processes from the same application")
                Toggle("Show system", isOn: $showSystemProcesses).toggleStyle(.checkbox)
                    .help("Include root-owned processes and executables in /System, /usr/libexec, /usr/sbin and /sbin. This classification is separate from termination protection.")
            }.controlSize(.small)
            .onChange(of: model.processSort) { _, _ in Task { await model.refresh() } }
            if model.processSort == .internet {
                if let error = model.processTrafficError { Text("Network activity unavailable: \(error)").font(.caption2).foregroundStyle(.red) }
            }
            if let error = model.processError { Text(error).foregroundStyle(.red) }
            if model.processes.isEmpty { ContentUnavailableView("Loading processes", systemImage: "gearshape.2") }
            let visibleProcesses = ProcessOrdering.rows(model.processes, by: model.processSort, descending: processSortDescending, showSystem: showSystemProcesses, search: search, traffic: model.processTraffic)
            if !groupProcesses && !model.processes.isEmpty && visibleProcesses.isEmpty { Text("No matching processes.").font(.caption).foregroundStyle(.secondary) }
            if groupProcesses {
                let groups = ProcessGrouping.groups(model.processes, by: model.processSort, descending: processSortDescending, showSystem: showSystemProcesses, search: search, traffic: model.processTraffic)
                if !model.processes.isEmpty && groups.isEmpty { Text("No matching groups.").font(.caption).foregroundStyle(.secondary) }
                LazyVStack(spacing: 8) {
                    ForEach(groups) { group in
                        if group.members.count == 1 { processRow(group.members[0]) }
                        else { processGroup(group) }
                    }
                }
            } else {
                LazyVStack(spacing: 8) { ForEach(visibleProcesses) { row in processRow(row) } }
            }
        }
    }
    private func processActions(protected: Bool, kill: @escaping () -> Void, force: @escaping () -> Void, info: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if protected {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    .frame(width: 62).help("Includes protected processes")
            } else {
                Button(role: .destructive, action: kill) {
                    Label("Kill", systemImage: "xmark").foregroundStyle(.red).frame(width: 44)
                }.controlSize(.small).frame(width: 62)
            }
            Menu {
                Button("Process details…", action: info)
                if !protected {
                    Divider()
                    Button("Force Kill…", role: .destructive, action: force)
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                .accessibilityLabel("Process actions")

        }.frame(width: 94)
    }
    private func processRow(_ row: ProcessRow) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(nsImage: row.app?.icon ?? NSWorkspace.shared.icon(for: .application)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(row.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if row.isSystem { Text("System").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
                    }
                    Text("PID \(row.id) • \(String(format: "%.1f",row.cpu))% CPU").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if model.processSort == .internet {
                        if let traffic = model.processTraffic[row.id] { Text("↓ \(bytes(traffic.received))  ↑ \(bytes(traffic.sent))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                        else { Text("Network: unavailable").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 4)
                processActions(protected: row.protected,
                               kill: { model.terminate(row, force: false) },
                               force: { forceTarget = row },
                               info: { ProcessInfoWindow.show(name: row.name, rows: [row], traffic: model.processTraffic) })

            }
            MemoryUsageBar(used: row.memory, total: model.system.totalRAM)
        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private func processGroup(_ group: ProcessGroup) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
            Button {
                if expandedGroups.contains(group.id) { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expandedGroups.contains(group.id) ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Image(nsImage: group.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) } ?? group.members[0].app?.icon ?? NSWorkspace.shared.icon(for: .application)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(group.members.count) processes • \(String(format: "%.1f", group.cpu))% CPU").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if group.isSystem { Text("System").font(.caption2).foregroundStyle(.secondary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(expandedGroups.contains(group.id) ? "Collapse" : "Expand") \(group.name), \(group.members.count) processes")
            processActions(protected: group.members.contains(where: { $0.protected }),
                           kill: { groupForce = false; groupTarget = group },
                           force: { groupForce = true; groupTarget = group },
                           info: { ProcessInfoWindow.show(name: group.name, rows: group.members, traffic: model.processTraffic) })

            }
            MemoryUsageBar(used: group.memory, total: model.system.totalRAM)
            if model.processSort == .internet {
                if let traffic = group.traffic(model.processTraffic) {
                    Text("↓ \(bytes(traffic.received))  ↑ \(bytes(traffic.sent)) • visible \(group.trafficCount(model.processTraffic))/\(group.members.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                } else { Text("Network: unavailable").font(.caption2).foregroundStyle(.secondary) }
            }
            if expandedGroups.contains(group.id) {
                ForEach(group.members) { row in processRow(row).padding(.leading, 12).padding(.trailing, -10) }
            }
        }.padding(10).background(.teal.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
    var foldersView: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Quick Access").font(.headline)
                Spacer()
                Menu {
                    Button("Add file…", systemImage: "doc.badge.plus") { folders.choose(files: true) }
                    Button("Add folder…", systemImage: "folder.badge.plus") { folders.choose() }
                } label: { Label("Add", systemImage: "plus") }.fixedSize()
            }
            if folders.folders.isEmpty { ContentUnavailableView("Your shortcuts, one click away", systemImage: "bolt", description: Text("Add files or folders to open them quickly.")) }
            LazyVStack(spacing: 8) {
                ForEach(folders.folders) { folder in
                    FolderShortcutRow(folder: folder, store: folders)
                }
            }
        }
    }
    var internetView: some View {
        VStack(spacing: 14) {
            Card(title: "Network settings", info: "HTTP, HTTPS and SOCKS apply to the selected network service, independently of terminal settings. Restore Defaults disables all three; each row also has its own reset. DNS and saved server addresses are preserved. macOS may request authorization. Authenticated proxies must be managed in System Settings.") {
                Picker("Network service", selection: $model.service) { ForEach(model.services,id: \.self) { Text($0) } }.onChange(of: model.service) { old, new in if old != new { model.readService() } }
                if let config = model.config {
                    ForEach(config.proxies.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle(config.proxies[i].title, isOn: proxyBinding(i, \.enabled))
                                Spacer()
                                Button { proxyResetService = config.service; proxyResetTarget = config.proxies[i].kind } label: { Image(systemName: "arrow.counterclockwise") }
                                    .buttonStyle(.borderless).help("Restore \(config.proxies[i].title) defaults")
                                    .accessibilityLabel("Restore \(config.proxies[i].title) defaults")
                            }
                            HStack { TextField("Host", text: proxyBinding(i, \.host)); TextField("Port", text: proxyBinding(i, \.port)).frame(width: 65) }.textFieldStyle(.roundedBorder)
                        }
                    }
                } else { Text("No network settings yet. Try Refresh.").foregroundStyle(.secondary) }
                HStack { Button("Refresh") { model.loadNetwork() }; Button("Apply proxy & DNS…") { model.applyNetwork() }.disabled(model.config == nil || model.busy); Button("Restore Defaults…") { proxyResetService = model.service; proxyResetTarget = "all" }.disabled(model.config == nil || model.busy); Menu { Button("Restore backup…") { model.applyNetwork(restore: true) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.config == nil || model.busy) }.controlSize(.small)
            }
            Card(title: "Terminal proxy", info: "Save writes a managed block to ~/.zshrc after making a backup. Existing terminals keep their environment; copy the command below or open a new terminal. Restore Defaults turns off macino’s proxy variables and clears its saved fields, preserving unrelated shell configuration. Restore File replaces the whole .zshrc with its last backup. Other shells require the copied command.") {
                Toggle("Enable in saved shell configuration", isOn: $terminal.enabled)
                TextField("http_proxy • http://127.0.0.1:8080", text: $terminal.http).textFieldStyle(.roundedBorder)
                TextField("https_proxy • http://127.0.0.1:8080", text: $terminal.https).textFieldStyle(.roundedBorder)
                TextField("all_proxy • socks5://127.0.0.1:1080", text: $terminal.all).textFieldStyle(.roundedBorder)
                TextField("no_proxy", text: $terminal.bypass).textFieldStyle(.roundedBorder)
                HStack { Button("Save for new terminals") { do { model.message = try terminal.save() } catch { model.message = error.localizedDescription } }; Button("Restore Defaults…") { proxyResetTarget = "terminal" }; Menu { Button("Restore file from backup…") { restoreShell = true } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize() }.controlSize(.small)
                DisclosureGroup("Command for current session") { Text(terminal.command).font(.system(size: 10, design: .monospaced)).textSelection(.enabled); Button("Copy command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(terminal.command, forType: .string) } }
            }
            Card(title: "Connection", info: "The check makes an HTTPS request to captive.apple.com. Success verifies that endpoint at that moment, not every website. This is separate from local network connectivity.") {
                Label(model.localStatus, systemImage: "network").font(.caption)
                Text(model.internetStatus).font(.caption).foregroundStyle(.secondary)
                Button("Check internet access") { model.checkInternet() }.disabled(model.busy)
            }
            Card(title: "DNS • \(model.service)", info: "Enter DNS server IPs in priority order, one per line. Automatic clears the draft; Apply saves it. Apply Proxy & DNS applies both sections and backs up the previous service settings. Flush DNS requests administrator authorization. Effective resolvers include all services and VPNs.") {
            Button("Flush DNS cache…") { model.operation { m in try await Task.detached { try Shell.admin([["/usr/bin/dscacheutil", "-flushcache"], ["/usr/bin/killall", "-HUP", "mDNSResponder"]]) }.value; m.message = "DNS cache flush commands completed successfully." } }
            Divider()
                TextEditor(text: $model.dnsDraft).font(.system(size: 12, design: .monospaced)).frame(height: 78).overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
                HStack { Button("Automatic") { model.dnsDraft = "" }; Button("Apply proxy & DNS…") { model.applyNetwork() }.disabled(model.config == nil || model.busy) }
                DisclosureGroup("Effective resolvers • all services and VPNs") { Text(model.effectiveDNS.isEmpty ? "Unavailable" : model.effectiveDNS).font(.system(size: 10, design: .monospaced)).textSelection(.enabled) }
            }

        }.disabled(model.busy)
    }
    func menuBinding(_ metric: MenuMetric) -> Binding<Bool> {
        Binding(get: { model.menuMetrics.contains(metric) }, set: { enabled in
            if enabled { model.menuMetrics.insert(metric) } else { model.menuMetrics.remove(metric) }
        })
    }
    func proxyBinding<T>(_ i: Int, _ key: WritableKeyPath<ProxyConfig, T>) -> Binding<T> { Binding(get: { model.config!.proxies[i][keyPath: key] }, set: { model.config?.proxies[i][keyPath: key] = $0 }) }
}

struct NativeGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9)) } else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)) }
    }
}
