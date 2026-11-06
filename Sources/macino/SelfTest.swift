import Foundation
import Darwin
import SwiftUI
import AppKit

enum SelfTest {
    @MainActor static func run() throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws { if !condition() { throw AppError.message("Self-test failed: " + message) }; print("PASS " + message) }
        try require(ClipboardShortcutLayout.matches(keyCode: 9, flags: .maskSecondaryFn), "Clipboard recognizes Fn-V")
        try require(!ClipboardShortcutLayout.matches(keyCode: 9, flags: .maskCommand) && !ClipboardShortcutLayout.matches(keyCode: 9, flags: [.maskSecondaryFn, .maskCommand]) && !ClipboardShortcutLayout.matches(keyCode: 8, flags: .maskSecondaryFn), "Clipboard shortcut leaves regular paste and other keys untouched")
        try require(ClipboardShortcutLayout.matches(keyCode: 9, flags: [.maskSecondaryFn, .maskShift]) && ClipboardShortcutLayout.matches(keyCode: 9, flags: [.maskSecondaryFn, .maskAlphaShift]), "Clipboard shortcut works with lowercase, Shift and Caps Lock")
        try require(ClipboardShortcutLayout.matches(keyCode: 9, flags: [.maskCommand, .maskShift], configuredKey: 9, modifiers: [.maskCommand, .maskShift]), "Custom shortcut accepts Command-Shift-V")
        try require(!ClipboardShortcutLayout.matches(keyCode: 9, flags: .maskCommand, configuredKey: 9, modifiers: [.maskCommand, .maskShift]), "Custom shortcut does not intercept regular paste")
        try require(ClipboardShortcutLayout.matches(keyCode: 11, flags: [.maskControl, .maskAlternate, .maskAlphaShift], configuredKey: 11, modifiers: [.maskControl, .maskAlternate]), "Custom shortcut supports other keys and ignores Caps Lock")
        let quickBounds = NSRect(x: -1000, y: -500, width: 1000, height: 700)
        for point in [NSPoint(x: -5, y: -495), NSPoint(x: -990, y: 190)] {
            let quickOrigin = ClipboardShortcutLayout.origin(near: point, size: NSSize(width: 310, height: 320), bounds: quickBounds)
            try require(quickBounds.contains(NSRect(origin: quickOrigin, size: NSSize(width: 310, height: 320))), "Quick clipboard stays within screen edges on secondary displays")
        }
        let clipboardDomain = "local.macino.clipboard.test." + UUID().uuidString
        let clipboardDefaults = UserDefaults(suiteName: clipboardDomain)!
        let clipboardBoard = NSPasteboard.withUniqueName()
        defer { clipboardDefaults.removePersistentDomain(forName: clipboardDomain); clipboardBoard.releaseGlobally() }
        let clipboard = ClipboardHistory(defaults: clipboardDefaults, pasteboard: clipboardBoard)
        clipboardBoard.setString("before opt-in", forType: .string)
        clipboard.poll()
        try require(clipboard.entries.isEmpty, "Clipboard does not capture before opt-in")
        clipboard.enabled = true
        clipboard.poll()
        try require(clipboard.entries.isEmpty, "Clipboard does not import pre-existing clipboard text")
        for value in ["First copied text", "Hello", "First copied text"] {
            clipboardBoard.clearContents(); clipboardBoard.setString(value, forType: .string); clipboard.poll()
        }
        try require(clipboard.entries.count == 2 && clipboard.entries.first?.text == "First copied text", "Clipboard deduplicates text newest first")
        clipboardBoard.clearContents(); clipboardBoard.setString("secret", forType: .string)
        clipboardBoard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")); clipboard.poll()
        try require(clipboard.entries.count == 2, "Clipboard skips confidential items")
        for index in 0..<60 {
            clipboardBoard.clearContents(); clipboardBoard.setString("Item \(index)", forType: .string); clipboard.poll()
        }
        try require(clipboard.entries.count == 50 && clipboard.entries.first?.text == "Item 59", "Clipboard history is bounded to 50 items")
        clipboard.copy(clipboard.entries[2]); clipboard.poll()
        try require(clipboard.entries.count == 50 && clipboardBoard.string(forType: .string) == "Item 57", "Clipboard restores an item without recording itself")
        clipboard.enabled = false
        try require(clipboard.entries.isEmpty && !clipboardDefaults.bool(forKey: "clipboardHistoryEnabled"), "Disabling clipboard history clears memory and persists opt-out")
        let adbFixture = "List of devices attached\nusb-123 device product:panther model:Pixel_7 device:panther transport_id:1\nlocked-456 unauthorized usb:2-1\noffline-789 offline\n"
        let screenPhones = AndroidScreenDevice.parse(adbFixture)
        try require(screenPhones.count == 3 && screenPhones[0].name == "Pixel 7" && screenPhones[0].authorized && !screenPhones[1].authorized && !screenPhones[2].authorized, "Android device parser separates ready, unauthorized and offline phones")
        try require(AndroidScreenDevice.parse("List of devices attached\n\n").isEmpty, "Android device parser does not invent a connected phone")
        let ipv4Endpoint = try AndroidModel.wifiEndpoint(host: "192.168.1.20", port: "37123")
        try require(ipv4Endpoint == "192.168.1.20:37123", "Android Wi-Fi accepts an explicit IPv4 connection endpoint")
        let ipv6Endpoint = try AndroidModel.wifiEndpoint(host: "fe80::1", port: "40000")
        try require(ipv6Endpoint == "[fe80::1]:40000", "Android Wi-Fi formats IPv6 endpoints with brackets")
        do { _ = try AndroidModel.wifiEndpoint(host: "192.168.1.20;echo test", port: "5555"); throw AppError.message("Invalid Wi-Fi host was accepted") } catch let error as AppError { if error.localizedDescription.contains("was accepted") { throw error } }
        do { _ = try AndroidModel.wifiEndpoint(host: "192.168.1.20", port: "70000"); throw AppError.message("Invalid Wi-Fi port was accepted") } catch let error as AppError { if error.localizedDescription.contains("was accepted") { throw error } }
        let wifiPhones = AndroidScreenDevice.parse("192.168.1.20:37123 device model:Pixel_7\nadb-example._adb-tls-connect._tcp device model:Pixel_8\n")
        try require(wifiPhones.count == 2 && wifiPhones.allSatisfy { $0.wireless }, "Android recognizes IP and mDNS wireless transports")
        try require(PanelDismissalPolicy.canDismiss(inlineDialog: false, nativeModal: false, attachedSheet: false), "menu dismisses normally when no dialog is open")
        try require(!PanelDismissalPolicy.canDismiss(inlineDialog: true, nativeModal: false, attachedSheet: false) && !PanelDismissalPolicy.canDismiss(inlineDialog: false, nativeModal: true, attachedSheet: false) && !PanelDismissalPolicy.canDismiss(inlineDialog: false, nativeModal: false, attachedSheet: true), "inline dialogs, native modal panels and sheets prevent automatic menu dismissal")
        var confirmedDialog = 0, cancelledDialog = 0
        let dialogFixture = InAppDialog(title: "Fixture", message: "Fixture", cancel: { cancelledDialog += 1 }) { confirmedDialog += 1 }
        dialogFixture.dismiss()
        try require(cancelledDialog == 1 && confirmedDialog == 0, "dialog dismissal cancels without executing its destructive action")
        let messageFixture = InAppDialog(title: "Fixture", message: "Fixture") { confirmedDialog += 1 }
        messageFixture.dismiss()
        try require(confirmedDialog == 1, "message dismissal executes its acknowledgment callback")
        try require(ReaderSpeedScale.speed(at: 0.5) == 1 && ReaderSpeedScale.position(for: 1) == 0.5, "Reader slider center is exactly normal speed")
        try require(ReaderSpeedScale.speed(at: 0) == 0.5 && ReaderSpeedScale.speed(at: 1) == 2, "Reader speed endpoints remain playable")
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            try require(abs(ReaderSpeedScale.speed(at: ReaderSpeedScale.position(for: speed)) - speed) < 0.0001, "Reader speed mapping round-trips")
        }
        let mixedSpeech = ReaderText.parts("سلام world، امروز English می‌خوانیم.")
        try require(mixedSpeech.map(\.language) == [.persian, .english, .persian, .english, .persian], "Reader switches voices within a mixed Persian and English sentence")
        try require(ReaderText.parts("1234. Hello!").first?.language == .english && ReaderText.parts("1234. سلام!").first?.language == .persian, "Reader assigns leading neutral text to the following language")
        let readerSentences = ReaderText.sentences("سلام دنیا. Hello world! آیا آماده‌ای؟\n\nYes, 3.14 is a number.")
        try require(readerSentences.count == 4 && readerSentences.last?.text.contains("3.14") == true, "Reader separates Persian and English sentences without splitting decimal numbers")
        try require(ReaderText.parts(String(repeating: "سلام English ", count: 200)).allSatisfy { $0.text.count <= 350 }, "Reader keeps generation segments bounded instead of rendering a whole file")
        try require(!PanelDismissalPolicy.canDismiss(inlineDialog: false, nativeModal: false, attachedSheet: false, stickyTab: true), "Reader tab stays open on outside clicks independently of dialog state")
        let readerTestDomain = "local.macino.selftest.reader." + UUID().uuidString
        let readerDefaults = UserDefaults(suiteName: readerTestDomain)!
        defer { readerDefaults.removePersistentDomain(forName: readerTestDomain) }
        let readerFixture = ReaderModel(defaults: readerDefaults)
        readerFixture.speed = 1.25
        try require(readerFixture.speed == 1.25 && readerFixture.state == .idle && readerFixture.sentences.isEmpty, "Reader speed changes do not start loading voices or documents")
        readerFixture.draftText = "سلام دنیا. Hello world!"
        try require(readerFixture.loadTypedText() && readerFixture.sentences.count == 2 && readerFixture.filename == "Typed text", "Reader prepares typed bilingual text for sentence highlighting")
        try require(!readerFixture.hasPlaybackResources && readerFixture.voiceProcessID == nil && readerFixture.state == .idle, "Typing and preparing text do not load voices or audio")
        readerFixture.draftText = "   "
        try require(!readerFixture.loadTypedText() && readerFixture.sentences.count == 2, "Empty typed input preserves the current document")
        readerFixture.closeDocument()
        try require(readerFixture.draftText.isEmpty && readerFixture.sentences.isEmpty, "Closing Reader clears the typed draft and document")
        readerFixture.speed = 9
        try require(readerFixture.speed == 2, "Reader clamps out-of-range speed without recursive updates")
        readerFixture.speed = .nan
        try require(readerFixture.speed == 1, "Reader recovers safely from a non-finite saved rate")
        let speechShape = MenuBubbleView.outline(size: NSSize(width: 480, height: 660), pointerX: 240)
        try require(speechShape.contains(CGPoint(x: 240, y: 658)) && !speechShape.contains(CGPoint(x: 100, y: 658)), "menu bubble has a visible pointed tip and transparent space beside it")
        let legacyBubble = GlassHostingController(rootView: Text("Bubble"), useLegacyMaterial: true, menuBubble: true)
        try require(legacyBubble.view is MenuBubbleView && legacyBubble.view.subviews.first is NSVisualEffectView, "menu speech bubble also wraps the legacy material fallback")
        let expandingPanel = MenuPanel()
        let originalFrame = NSRect(x: 500, y: 100, width: MenuPanel.contentWidth, height: 650)
        expandingPanel.setFrame(originalFrame, display: false)
        expandingPanel.setNetworkExpanded(true)
        try require(expandingPanel.frame.width == MenuPanel.contentWidth + MenuPanel.networkWidth && expandingPanel.frame.maxX == originalFrame.maxX, "network drawer expands the native window to the left without covering main content")
        expandingPanel.setNetworkExpanded(false)
        try require(expandingPanel.frame == originalFrame, "closing the network drawer restores the original window frame")
        let glass = GlassHostingController(rootView: Text("Test"))
        if #available(macOS 26.0, *) { try require(glass.view.subviews.contains(where: { $0 is NSGlassEffectView }), "root container uses native Apple Liquid Glass") }
        else { try require(glass.view is NSVisualEffectView, "root container uses native material fallback") }
        let legacyGlass = GlassHostingController(rootView: Text("Legacy"), useLegacyMaterial: true)
        try require(legacyGlass.view is NSVisualEffectView, "pre-Liquid Glass material fallback renders on the current host")
        let m1Keys = CPUTemperature.sensorKeys(for: "Apple M1")
        try require(m1Keys.contains("Tp09") && m1Keys.contains("Tp01") && !m1Keys.contains("Tp00"), "M1 maps CPU core sensors without M5-only keys")
        for generation in 1...5 {
            let base = CPUTemperature.sensorKeys(for: "Apple M\(generation)")
            try require(!base.isEmpty && ["Pro", "Max", "Ultra"].allSatisfy { CPUTemperature.sensorKeys(for: "Apple M\(generation) " + $0) == base }, "M\(generation) family sensor selection covers chip suffixes")
        }
        try require(CPUTemperature.sensorKeys(for: "Apple M10").isEmpty, "unknown chip generation cannot accidentally use M1 sensors")
        var degrees: Float = 42.5
        let floatBytes = withUnsafeBytes(of: &degrees) { Array($0) }
        try require(CPUTemperature.decode(type: 0x666c7420, data: floatBytes) == 42.5 && CPUTemperature.decode(type: 0x73703738, data: [42, 128]) == 42.5, "SMC Float and signed fixed-point temperatures decode consistently")
        try require(CPUTemperature.decode(type: 0x73703738, data: [255, 0]) == nil && CPUTemperature.decode(type: 0x666c7420, data: [0]) == nil && CPUTemperature.decode(type: 0, data: floatBytes) == nil, "invalid sensor type, size and negative values remain unavailable")
        try require(SetupModel.isInstalled(URL(fileURLWithPath: "/Applications/macino.app")) && !SetupModel.isInstalled(URL(fileURLWithPath: "/Volumes/Installer/macino.app")) && !SetupModel.isInstalled(URL(fileURLWithPath: "/ApplicationsBackup/macino.app")), "setup distinguishes installed apps from mounted and development copies")
        let menuSelection: Set<MenuMetric> = [.storage, .cpu, .memory]
        try require(MenuMetric.selected(menuSelection) == [.cpu, .memory, .storage], "menu metrics keep a stable horizontal order")
        try require(MenuMetricsImage.columns([.cpu, .memory]) == [[.cpu, .memory]], "two menu metrics stack in one column")
        try require(MenuMetricsImage.columns(Set(MenuMetric.allCases)) == [[.cpu, .gpu], [.memory, .storage]], "four menu metrics form two paired columns")
        try require(MenuMetricsImage.columns([.cpu, .gpu, .memory]) == [[.cpu, .gpu], [.memory]], "odd menu metric selection retains its last column")
        var menuSnapshot = SystemSnapshot()
        menuSnapshot.cpu = 23.5; menuSnapshot.usedRAM = 16 * 1_073_741_824
        menuSnapshot.diskTotal = 500 * 1_073_741_824; menuSnapshot.diskFree = 200 * 1_073_741_824
        try require(MenuMetric.memory.value(in: menuSnapshot) == "16.0 GB" && MenuMetric.storage.value(in: menuSnapshot) == "300 GB", "menu memory and storage show compact used capacity with units")
        try require(MenuMetric.gpu.value(in: menuSnapshot) == "—" && MenuMetric.cpu.value(in: SystemSnapshot()) == "—", "unavailable and warming-up menu metrics do not show invented zeroes")
        let metricIcon = NSImage(size: NSSize(width: 22, height: 22))
        let stacked = MenuMetricsImage.make(icon: metricIcon, snapshot: menuSnapshot, selection: Set(MenuMetric.allCases))
        try require(stacked.isTemplate && stacked.size.height == 22 && stacked.size.width < 240, "stacked menu rendering stays compact and uses native template colors")
        let snapshot = SystemSampler().sample()
        try require(snapshot.totalRAM > 0 && snapshot.diskTotal > 0 && snapshot.diskFree <= snapshot.diskTotal, "physical memory and filesystem metrics")
        try require(snapshot.gpu == nil || (0...100).contains(snapshot.gpu!), "optional GPU counter bounds")
        try require(snapshot.swapUsed != nil && snapshot.wiredRAM != nil && snapshot.compressedRAM != nil, "native swap and VM detail reads")
        var history = ResourceHistory()
        for tick in 0..<125 { history.append(SystemSnapshot(), at: Date(timeIntervalSince1970: Double(tick))) }
        try require(history.points.count == 120 && history.points.first?.date == Date(timeIntervalSince1970: 5), "history bounds memory and discards oldest samples")
        try require(history.points.allSatisfy { $0.cpu == nil && $0.temperature == nil }, "history preserves unavailable samples instead of inventing zeros")
        let reportRow = ProcessRow(id: 987654, uid: getuid(), cpu: 1.5, memory: 1024, command: "/tmp/a\"b\nc", started: "fixture")
        let reportData = try ProcessReport.data(rows: [reportRow], traffic: [:])
        let reportJSON = try JSONSerialization.jsonObject(with: reportData) as! [[String: Any]]
        try require(reportJSON[0]["executable"] as? String == reportRow.command && reportJSON[0]["receivedBytes"] == nil, "JSON report escapes paths and preserves missing network data")
        let processes = try ProcessManager.sample()
        try require(processes.contains(where: { $0.id == getpid() && $0.protected }), "macino process is protected")
        let homeRow = ProcessRow(id: 987650, uid: getuid(), cpu: 0, memory: 0, command: "/System/Applications/Home.app/Contents/MacOS/Home", started: "fixture")
        let calculatorRow = ProcessRow(id: 987651, uid: getuid(), cpu: 0, memory: 0, command: "/System/Applications/Calculator.app/Contents/MacOS/Calculator", started: "fixture")
        try require(homeRow.isSystem && !homeRow.protected && !calculatorRow.protected, "ordinary Apple apps remain system-classified but are eligible for Kill")
        try require(!ProcessTerminationPolicy.isProtected(pid: 987652, uid: getuid(), executable: "/usr/libexec/noncritical-helper"), "system helper location alone does not block termination")
        try require(ProcessTerminationPolicy.criticalExecutables.allSatisfy { ProcessTerminationPolicy.isProtected(pid: 987653, uid: getuid(), executable: "/System/Library/CoreServices/" + $0) }, "critical process protection uses executable identity independent of localized app names")
        try require(ProcessTerminationPolicy.isProtected(pid: 1, uid: getuid(), executable: "/sbin/launchd") && ProcessTerminationPolicy.isProtected(pid: 987654, uid: getuid() == 0 ? 501 : 0, executable: homeRow.command), "PID 1 and another user's Apple app remain protected")
        let homeGroups = ProcessGrouping.groups([homeRow], by: .cpu, descending: true, showSystem: true, search: "", traffic: [:])
        try require(homeGroups.count == 1 && !homeGroups[0].members.contains(where: \.protected), "Home group is eligible for group Kill")
        if let own = processes.first(where: { $0.id == getpid() }) {
            var denied = false; do { try ProcessManager.terminate(own, force: true) } catch { denied = true }
            try require(denied, "protected termination rejected")
        }
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw AppError.message("Could not create test loopback socket") }
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try require(bound == 0 && listen(listener, 1) == 0, "disposable TCP listener binds only to loopback")
        if let own = processes.first(where: { $0.id == getpid() }) {
            let details = try ProcessDiagnostics.inspect(own)
            try require(details.connections.contains("LISTEN") && details.connections.contains("127.0.0.1"), "process diagnostics finds a real TCP listening endpoint")
        }
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["30"]; try child.run()
        defer { if child.isRunning { child.terminate() } }
        if let row = try ProcessManager.sample().first(where: { $0.id == child.processIdentifier }) {
            let diagnostic = try ProcessDiagnostics.inspect(row)
            try require(diagnostic.parent.hasPrefix("\(getpid()) ·") && !diagnostic.state.isEmpty, "process inspection reads the actual parent and state")
            try ProcessManager.terminate(row, force: false); child.waitUntilExit()
            try require(!child.isRunning, "graceful termination of test child")
            var denied = false; do { try ProcessManager.terminate(row, force: true) } catch { denied = true }
            try require(denied, "stale process identity rejected")
            var staleInspection = false
            do { _ = try ProcessDiagnostics.inspect(row) } catch { staleInspection = true }
            try require(staleInspection, "process inspection rejects exited identities")
        } else { throw AppError.message("Child process missing") }
        let sortFixtures = [
            ProcessRow(id: 900001, uid: getuid(), cpu: 12, memory: 3000, command: "/Applications/UserApp", started: "fixture"),
            ProcessRow(id: 900002, uid: 0, cpu: 5, memory: 8000, command: "/usr/libexec/fixture", started: "fixture"),
            ProcessRow(id: 900003, uid: getuid(), cpu: 40, memory: 1000, command: "/Applications/OtherApp", started: "fixture")
        ]
        let counters = ProcessTraffic.indexed([TrafficRow(id: "app.with.dots.900001", received: 20, sent: 30), TrafficRow(id: "helper.900002", received: 100, sent: 10)])
        func ordered(_ key: ProcessSort, _ descending: Bool = true, _ showSystem: Bool = true) -> [Int32] {
            ProcessOrdering.rows(sortFixtures, by: key, descending: descending, showSystem: showSystem, search: "", traffic: counters).map(\.id)
        }
        try require(ordered(.cpu) == [900003, 900001, 900002], "process CPU sort descending")
        try require(ordered(.memory, false) == [900003, 900001, 900002], "process RAM sort ascending")
        try require(ordered(.internet) == [900002, 900001, 900003] && ordered(.internet, false) == [900001, 900002, 900003], "network sort matches PID suffix and keeps unavailable counters last")
        try require(ordered(.system).first == 900002 && ordered(.system, false).last == 900002, "system grouping supports both directions")
        try require(ordered(.cpu, true, false) == [900003, 900001], "system checkbox filters without hiding user processes")
        let family = [
            ProcessRow(id: 910001, uid: getuid(), cpu: 3, memory: 100, command: "/Applications/Suite.app/Contents/MacOS/Suite", started: "fixture"),
            ProcessRow(id: 910002, uid: getuid(), cpu: 7, memory: 200, command: "/Applications/Suite.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", started: "fixture"),
            ProcessRow(id: 910003, uid: getuid(), cpu: 2, memory: 250, command: "/Other/Suite.app/Contents/MacOS/Suite", started: "fixture")
        ]
        let families = ProcessGrouping.groups(family, by: .memory, descending: true, showSystem: true, search: "", traffic: [:])
        try require(families.count == 2 && families[0].members.count == 2 && families[0].memory == 300 && families[0].cpu == 10, "grouping combines nested helpers and sorts by aggregate memory")
        try require(families[0].id != families[1].id, "same app names in distinct bundle paths stay separate")
        let familySearch = ProcessGrouping.groups(family, by: .cpu, descending: true, showSystem: true, search: "910002", traffic: [:])
        try require(familySearch.count == 1 && familySearch[0].members.count == 2, "group search retains complete family totals")
        let groupNetwork = families[0].traffic([910001: ProcessTraffic(received: 10, sent: 20)])
        try require(groupNetwork?.total == 30 && families[0].trafficCount([910001: ProcessTraffic(received: 10, sent: 20)]) == 1, "group traffic preserves partial visibility instead of inventing counters")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("macino-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let loginFile = temp.appendingPathComponent("login.plist")
        try require(LocalLoginAgent.isAdHoc(Bundle.main.bundleURL), "local signing is detected independently of login-item registration")
        try LocalLoginAgent.save(app: Bundle.main.bundleURL, file: loginFile)
        let loginPath = try LocalLoginAgent.savedApp(file: loginFile)
        try require(loginPath == Bundle.main.bundlePath, "local login configuration saves and reads back the exact app path")
        let loginPlist = try PropertyListSerialization.propertyList(from: Data(contentsOf: loginFile), format: nil) as! [String: Any]
        try require(loginPlist["RunAtLoad"] as? Bool == true && loginPlist["KeepAlive"] == nil, "local login starts once without a persistent background loop")
        try LocalLoginAgent.remove(file: loginFile)
        try require(!FileManager.default.fileExists(atPath: loginFile.path), "disabling local login removes its managed configuration")
        try Data("unrelated configuration".utf8).write(to: loginFile)
        var foreignFileRejected = false
        do { try LocalLoginAgent.save(app: Bundle.main.bundleURL, file: loginFile) } catch { foreignFileRejected = true }
        try require(foreignFileRejected, "local login preserves unrelated configuration files")
        try FileManager.default.removeItem(at: loginFile)
        let folder = temp.appendingPathComponent("Bookmark"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = FolderBookmark(data: try folder.bookmarkData(), originalPath: folder.path)
        let resolved = try bookmark.resolve().0
        try require(resolved.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path, "native folder bookmark resolution")
        let shortcutsDomain = "local.macino.selftest.shortcuts." + UUID().uuidString
        let shortcutDefaults = UserDefaults(suiteName: shortcutsDomain)!
        defer { shortcutDefaults.removePersistentDomain(forName: shortcutsDomain) }
        shortcutDefaults.set(try JSONEncoder().encode([bookmark]), forKey: "folders")
        let shortcutStore = FolderStore(defaults: shortcutDefaults)
        try require(shortcutStore.folders.count == 1 && shortcutStore.folders[0].id == bookmark.id, "Quick Access preserves existing folder bookmarks")
        let quickFile = temp.appendingPathComponent("Quick access.txt")
        try Data("shortcut fixture".utf8).write(to: quickFile)
        try shortcutStore.add([quickFile, quickFile])
        let reloadedShortcuts = FolderStore(defaults: shortcutDefaults)
        let fileURL = try reloadedShortcuts.folders.last!.resolve().0
        try require(reloadedShortcuts.folders.count == 2 && fileURL.resolvingSymlinksInPath() == quickFile.resolvingSymlinksInPath(), "Quick Access persists file bookmarks and avoids duplicate shortcuts")
        try shortcutStore.add([quickFile], replacing: bookmark.id)
        try require(shortcutStore.folders.count == 2 && shortcutStore.folders.first?.id == bookmark.id, "Quick Access relink does not duplicate an existing shortcut")
        try FileManager.default.removeItem(at: quickFile)
        let completion = try PathNavigator.suggestions(temp.path + "/boo")
        try require(completion.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL }, "Run suggests matching directories without case sensitivity")
        let destination = try PathNavigator.destination(folder.path)
        try require(destination.directory, "Run resolves an existing folder")
        var invalidPathRejected = false
        do { _ = try PathNavigator.destination("relative/path") } catch { invalidPathRejected = true }
        try require(invalidPathRejected, "Run rejects relative and command-like input")
        let home = try PathNavigator.expanded("~/")
        try require(home == NSHomeDirectory(), "Run expands home shorthand")
        let payload = temp.appendingPathComponent("cache.bin"); try Data(repeating: 7, count: 4096).write(to: payload)
        let link = temp.appendingPathComponent("symlink"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: FileManager.default.homeDirectoryForCurrentUser)
        let files = try Cleanup.regularFiles(temp)
        try require(files.count == 1 && files[0].resolvingSymlinksInPath() == payload.resolvingSymlinksInPath(), "cache scan excludes symbolic links")
        let deletion = Cleanup.clear(["fixture"], within: [CacheCategory(id: "fixture", title: "Temporary test fixture", url: temp)])
        try require(!FileManager.default.fileExists(atPath: payload.path) && FileManager.default.fileExists(atPath: link.path), "cache removal deletes fixture files and leaves symlinks untouched")
        try require(deletion.contains("Removed 1 files"), "cache deletion outcome reports actual successful count")
        let services = try NetworkSettings.services(); try require(!services.isEmpty, "network service discovery")
        if services.contains("Wi-Fi") { let config = try NetworkSettings.read("Wi-Fi"); try require(config.proxies.count == 3, "HTTP, HTTPS, SOCKS and DNS readback"); try NetworkSettings.validate(config) }
        let traffic = try NetworkActivity.sample(); try require(!traffic.isEmpty, "nettop traffic parsing")
        var terminal = TerminalProxy(); terminal.enabled = true; terminal.http = "http://127.0.0.1:8080"
        try require(terminal.command.contains("export http_proxy='http://127.0.0.1:8080'"), "terminal command generation")
        let shellFile = temp.appendingPathComponent(".zshrc")
        let original = "# personal configuration\nexport EDITOR=vim\n"
        try original.write(to: shellFile, atomically: true, encoding: .utf8)
        _ = try terminal.save(to: shellFile, stateURL: temp.appendingPathComponent("state.json"), recordBackup: false)
        let savedShell = try String(contentsOf: shellFile, encoding: .utf8)
        try require(savedShell.hasPrefix(original) && savedShell.contains(TerminalProxy.begin), "shell save preserves unrelated configuration")
        terminal.enabled = false
        _ = try terminal.save(to: shellFile, stateURL: temp.appendingPathComponent("state.json"), recordBackup: false)
        let disabledShell = try String(contentsOf: shellFile, encoding: .utf8)
        try require(disabledShell.components(separatedBy: TerminalProxy.begin).count == 2 && disabledShell.contains("unset http_proxy"), "shell disable replaces managed block once")
        let backups = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("macino-backup") }
        try require(backups.count == 2, "shell backups created before both edits")
        let restoredTerminal = try TerminalProxy.restoreDefaults(to: shellFile, stateURL: temp.appendingPathComponent("state.json"), recordBackup: false)
        let resetShell = try String(contentsOf: shellFile, encoding: .utf8)
        let resetState = try JSONDecoder().decode(TerminalProxy.self, from: Data(contentsOf: temp.appendingPathComponent("state.json")))
        try require(!restoredTerminal.enabled && restoredTerminal.http.isEmpty && !resetState.enabled && resetState.all.isEmpty, "terminal defaults reset saved fields and disable proxy state")
        try require(resetShell.hasPrefix(original) && resetShell.contains("unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY") && !resetShell.contains("export http_proxy="), "terminal default reset preserves personal shell settings and unsets proxy variants")
        var resetSymlinkDenied = false
        do { _ = try TerminalProxy.restoreDefaults(to: link, stateURL: temp.appendingPathComponent("ignored.json"), recordBackup: false) } catch { resetSymlinkDenied = true }
        try require(resetSymlinkDenied, "terminal defaults refuse a symlink destination")
        let resetCommands = try NetworkSettings.proxyDefaultCommands("Fixture Service")
        try require(resetCommands.count == 3 && resetCommands.allSatisfy { $0.count == 4 && $0[2] == "Fixture Service" && $0[3] == "off" && $0[1].hasSuffix("proxystate") }, "all-proxy reset only disables proxy states without DNS or server writes")
        let singleReset = try NetworkSettings.proxyDefaultCommands("Fixture Service", kind: "secureweb")
        try require(singleReset == [["/usr/sbin/networksetup", "-setsecurewebproxystate", "Fixture Service", "off"]], "per-proxy defaults target only the selected protocol")
        var invalidResetDenied = false
        do { _ = try NetworkSettings.proxyDefaultCommands("Fixture Service", kind: "dnsservers") } catch { invalidResetDenied = true }
        try require(invalidResetDenied, "proxy defaults reject unknown operation types")
        try require(Shell.quote("a'b") == "'a'\\''b'", "shell argument quoting")
        print("SELF-TEST COMPLETE — no user network or shell settings modified")
    }
}
