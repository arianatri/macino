import AppKit
import SwiftUI
import ApplicationServices
import Combine
import Carbon

enum ClipboardShortcutLayout {
    static func matches(keyCode: Int64, flags: CGEventFlags, configuredKey: Int64 = 9, modifiers: CGEventFlags = .maskSecondaryFn) -> Bool {
        var actual = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn])
        if !modifiers.contains(.maskShift) { actual.remove(.maskShift) }
        return keyCode == configuredKey && actual == modifiers
    }
    static func origin(near point: NSPoint, size: NSSize, bounds: NSRect) -> NSPoint {
        let x = min(max(point.x, bounds.minX), bounds.maxX - size.width)
        let y = point.y - size.height - 8 >= bounds.minY ? point.y - size.height - 8 : min(point.y + 24, bounds.maxY - size.height)
        return NSPoint(x: max(bounds.minX, x), y: max(bounds.minY, y))
    }
}

private final class ClipboardShortcutState: @unchecked Sendable {
    private let lock = NSLock()
    private var code: Int64 = 9
    private var modifiers: CGEventFlags = .maskSecondaryFn
    func set(code: Int64, modifiers: CGEventFlags) { lock.lock(); defer { lock.unlock() }; self.code = code; self.modifiers = modifiers }
    func matches(_ event: CGEvent) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ClipboardShortcutLayout.matches(keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags, configuredKey: code, modifiers: modifiers)
    }
}

private func clipboardCarbonCallback(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<ClipboardQuickPanel>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { controller.toggle() }
    return noErr
}

private func clipboardShortcutCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ClipboardQuickPanel>.fromOpaque(context).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { controller.resumeTap() }
        return Unmanaged.passUnretained(event)
    }
    if controller.shortcutState.matches(event) {
        if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { controller.toggle() }
        }
        return nil
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class ClipboardQuickPanel: ObservableObject {
    static let shared = ClipboardQuickPanel()
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "clipboardQuickShortcut"); configure(prompt: false) }
    }
    @Published private(set) var permissionNeeded = false
    @Published private(set) var recording = false
    @Published private(set) var shortcutLabel = ""
    @Published private(set) var shortcutStatus = ""
    fileprivate nonisolated let shortcutState = ClipboardShortcutState()
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var recordingMonitor: Any?
    private var activationObserver: AnyCancellable?
    private var keyCode: UInt32 = 9
    private var modifiers: CGEventFlags = .maskSecondaryFn
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var panel: QuickClipboardWindow?
    private var outside: Any?
    private var local: Any?
    private var subscription: AnyCancellable?
    private var target: NSRunningApplication?
    init() {
        enabled = UserDefaults.standard.bool(forKey: "clipboardQuickShortcut")
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "clipboardShortcutKey") != nil {
            keyCode = UInt32(clamping: defaults.integer(forKey: "clipboardShortcutKey"))
            modifiers = CGEventFlags(rawValue: UInt64(bitPattern: Int64(defaults.integer(forKey: "clipboardShortcutModifiers"))))
            shortcutLabel = defaults.string(forKey: "clipboardShortcutLabel") ?? "Shortcut"
        } else {
            keyCode = 9; modifiers = .maskControl; shortcutLabel = "⌃V"
        }
        activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            guard let self, self.enabled, !self.recording else { return }
            self.configure(prompt: false)
        }
        subscription = ClipboardHistory.shared.$enabled.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.configure(prompt: false)
        }
        configure(prompt: false)
    }
    func configure(prompt: Bool) {
        dismiss()
        if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }; hotKeyHandler = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; permissionNeeded = false
        shortcutStatus = ""
        guard enabled, ClipboardHistory.shared.enabled, !recording else { return }
        shortcutState.set(code: Int64(keyCode), modifiers: modifiers)
        if !modifiers.contains(.maskSecondaryFn) {
            var carbonMods: UInt32 = 0
            if modifiers.contains(.maskCommand) { carbonMods |= UInt32(cmdKey) }
            if modifiers.contains(.maskControl) { carbonMods |= UInt32(controlKey) }
            if modifiers.contains(.maskAlternate) { carbonMods |= UInt32(optionKey) }
            if modifiers.contains(.maskShift) { carbonMods |= UInt32(shiftKey) }
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installed = InstallEventHandler(GetApplicationEventTarget(), clipboardCarbonCallback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
            let status = installed == noErr ? RegisterEventHotKey(keyCode, carbonMods, EventHotKeyID(signature: 0x4d434c50, id: 1), GetApplicationEventTarget(), 0, &hotKey) : installed
            if status != noErr { shortcutStatus = "That shortcut is already in use. Choose another."; return }
            permissionNeeded = !AXIsProcessTrusted()
            shortcutStatus = "Ready — press " + shortcutLabel
            return
        }
        guard AXIsProcessTrusted() else { permissionNeeded = true; shortcutStatus = "This Fn shortcut isn’t available. Try Control + V."; return }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue),
            callback: clipboardShortcutCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            permissionNeeded = !AXIsProcessTrusted()
            shortcutStatus = "Couldn’t start this shortcut. Try Control + V instead."
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        shortcutStatus = "Ready — press " + shortcutLabel
    }
    func startRecording() {
        stopRecording()
        recording = true
        configure(prompt: false)
        shortcutStatus = "Press your shortcut. Esc to cancel."
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); self.configure(prompt: false); return nil }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
            guard !flags.intersection([.command, .control, .option, .function]).isEmpty else {
                self.shortcutStatus = "Include ⌘, ⌥, Control or Fn with a key."; return nil
            }
            var modifiers: CGEventFlags = []
            if flags.contains(.command) { modifiers.insert(.maskCommand) }
            if flags.contains(.control) { modifiers.insert(.maskControl) }
            if flags.contains(.option) { modifiers.insert(.maskAlternate) }
            if flags.contains(.shift) { modifiers.insert(.maskShift) }
            if flags.contains(.function) { modifiers.insert(.maskSecondaryFn) }
            let prefix = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + (flags.contains(.function) ? "Fn " : "")
            let special: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            self.saveShortcut(key: UInt32(event.keyCode), modifiers: modifiers, label: prefix + key)
            return nil
        }
    }
    func stopRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil; recording = false
    }
    func useSuggestedShortcut() { saveShortcut(key: 9, modifiers: .maskControl, label: "⌃V") }
    private func saveShortcut(key: UInt32, modifiers: CGEventFlags, label: String) {
        guard !(key == 9 && modifiers == .maskCommand) else {
            shortcutStatus = "⌘V is for pasting. Choose a different shortcut."; return
        }
        stopRecording(); keyCode = key; self.modifiers = modifiers; shortcutLabel = label
        let defaults = UserDefaults.standard
        defaults.set(Int(key), forKey: "clipboardShortcutKey")
        defaults.set(Int64(bitPattern: modifiers.rawValue), forKey: "clipboardShortcutModifiers")
        defaults.set(label, forKey: "clipboardShortcutLabel")
        configure(prompt: false)
    }
    func refreshAccess() {
        let wasNeeded = permissionNeeded
        permissionNeeded = enabled && ClipboardHistory.shared.enabled && !AXIsProcessTrusted()
        if wasNeeded && !permissionNeeded && enabled && !recording { configure(prompt: false) }
    }
    func resumeTap() { if enabled, let tap { CGEvent.tapEnable(tap: tap, enable: true) } }
    func toggle() {
        guard enabled, ClipboardHistory.shared.enabled else { return }
        if panel?.isVisible == true { dismiss(); return }
        target = NSWorkspace.shared.frontmostApplication
        let point = caretPoint() ?? NSEvent.mouseLocation
        let window = panel ?? QuickClipboardWindow()
        panel = window
        window.contentView = NSHostingView(rootView: QuickClipboardView(history: .shared, choose: { [weak self] entry in self?.insert(entry) }, close: { [weak self] in self?.dismiss() }))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let bounds = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)).insetBy(dx: 8, dy: 8)
        window.setFrameOrigin(ClipboardShortcutLayout.origin(near: point, size: window.frame.size, bounds: bounds))
        window.makeKeyAndOrderFront(nil)
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.dismiss() }
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 { self?.dismiss(); return nil }
            if event.type != .keyDown && event.window !== self?.panel { self?.dismiss() }
            return event
        }
    }
    func dismiss() {
        panel?.orderOut(nil)
        if let outside { NSEvent.removeMonitor(outside) }; outside = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
    }
    private func insert(_ entry: ClipboardEntry) {
        ClipboardHistory.shared.copy(entry)
        let destination = target
        dismiss()
        guard let destination, destination.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        destination.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else { return }
            guard AXIsProcessTrusted() else { return }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }
    private func caretPoint() -> NSPoint? {
        guard let target else { return nil }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &rect), rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
        return NSPoint(x: rect.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - rect.maxY)
    }
}

private final class QuickClipboardWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 310, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; level = .popUpMenu; hidesOnDeactivate = false
        backgroundColor = .clear; isOpaque = false; hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }
}

private struct QuickClipboardView: View {
    @ObservedObject var history: ClipboardHistory
    let choose: (ClipboardEntry) -> Void
    let close: () -> Void
    @State private var search = ""
    @State private var closeHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Label("Clipboard", systemImage: "doc.on.clipboard").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.primary.opacity(closeHovered ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(closeHovered ? 0.22 : 0.12)))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help("Close").accessibilityLabel("Close clipboard")
                    .onHover { closeHovered = $0 }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: closeHovered)
            }
            TextField("Search…", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(history.entries.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }) { entry in
                        HStack(alignment: .top, spacing: 5) {
                            Button { choose(entry) } label: {
                                Text(entry.text).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Paste")
                            Button { history.remove(entry) } label: {
                                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                            }.buttonStyle(.borderless).help("Delete").accessibilityLabel("Delete copied text")
                        }.padding(9).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if history.entries.isEmpty { Text("Nothing copied yet").font(.caption).foregroundStyle(.secondary).padding(.top, 35) }
                }
            }
            Divider().opacity(0.4)
            HStack {
                Text(AXIsProcessTrusted() ? "Click to paste" : "Click to copy, then ⌘V")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { history.clear() } label: {
                    Label("Clear all", systemImage: "trash").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.75))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).disabled(history.entries.isEmpty)
                    .opacity(history.entries.isEmpty ? 0.45 : 1).help("Clear clipboard history")
            }
        }.padding(12).frame(width: 310, height: 320).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.10)).allowsHitTesting(false) }
            .overlay(alignment: .top) { ClipboardDragEdge().frame(height: 8) }
            .overlay(alignment: .bottom) { ClipboardDragEdge().frame(height: 8) }
            .overlay(alignment: .leading) { ClipboardDragEdge().frame(width: 8) }
            .overlay(alignment: .trailing) { ClipboardDragEdge().frame(width: 8) }
    }
}

/// Keep dragging on all four outer edges, away from paste/delete/search controls.
private struct ClipboardDragEdge: NSViewRepresentable {
    func makeNSView(context: Context) -> ClipboardDragHandle { ClipboardDragHandle() }
    func updateNSView(_ nsView: ClipboardDragHandle, context: Context) {}
}

private final class ClipboardDragHandle: NSView {
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Drag to move"
        setAccessibilityLabel("Move clipboard window")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            NSColor.secondaryLabelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        window?.performDrag(with: event)
    }
}
