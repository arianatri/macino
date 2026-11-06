import AppKit

enum PanelDismissalPolicy {
    static func canDismiss(inlineDialog: Bool, nativeModal: Bool, attachedSheet: Bool, stickyTab: Bool = false) -> Bool {
        !inlineDialog && !nativeModal && !attachedSheet && !stickyTab
    }
}

/// One transparent window hosts one native glass surface, without a second popover frame.
@MainActor final class MenuPanel: NSPanel {
    static let contentWidth: CGFloat = 680
    static let networkWidth: CGFloat = 300
    var dialogIsVisible = false
    var readerIsSelected = false
    var canDismissAutomatically: Bool {
        PanelDismissalPolicy.canDismiss(inlineDialog: dialogIsVisible, nativeModal: NSApp.modalWindow != nil, attachedSheet: attachedSheet != nil, stickyTab: readerIsSelected)
    }
    var canDismissExplicitly: Bool {
        PanelDismissalPolicy.canDismiss(inlineDialog: dialogIsVisible, nativeModal: NSApp.modalWindow != nil, attachedSheet: attachedSheet != nil)
    }
    private var anchorScreenX: CGFloat?
    private var collapsedFrame: NSRect?
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 660), styleMask: [.borderless], backing: .buffered, defer: false)
        title = "macino"
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        isReleasedWhenClosed = false; level = .statusBar
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }
    override func cancelOperation(_ sender: Any?) {
        if dialogIsVisible { NotificationCenter.default.post(name: .macinoCancelDialog, object: nil) }
        else { onDismiss?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with: event) }
    }
    func setNetworkExpanded(_ expanded: Bool) {
        guard (frame.width > Self.contentWidth) != expanded else { return }
        let target: NSRect
        if expanded {
            collapsedFrame = frame
            var next = frame
            next.size.width = Self.contentWidth + Self.networkWidth
            next.origin.x = frame.maxX - next.width
            if let bounds = screen?.visibleFrame.insetBy(dx: 8, dy: 8) {
                next.origin.x = max(bounds.minX, min(next.origin.x, bounds.maxX - next.width))
            }
            target = next
        } else {
            target = collapsedFrame ?? NSRect(x: frame.maxX - Self.contentWidth, y: frame.minY, width: Self.contentWidth, height: frame.height)
            collapsedFrame = nil
        }
        updateBubblePointer(rightEdge: target.maxX)
        setFrame(target, display: true, animate: isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    private func updateBubblePointer(rightEdge: CGFloat) {
        if let anchorScreenX, let bubble = contentViewController?.view as? MenuBubbleView {
            bubble.pointerDistanceFromRight = rightEdge - anchorScreenX
        }
    }
    func show(below button: NSStatusBarButton) {
        guard let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        anchorScreenX = anchor.midX
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(anchor.midX - (frame.width - Self.contentWidth / 2), bounds.minX), bounds.maxX - frame.width)
        let y = max(bounds.minY, min(anchor.minY - frame.height - 6, bounds.maxY - frame.height))
        setFrameOrigin(NSPoint(x: x, y: y))
        if frame.width > Self.contentWidth { collapsedFrame = NSRect(x: frame.maxX - Self.contentWidth, y: y, width: Self.contentWidth, height: frame.height) }
        updateBubblePointer(rightEdge: frame.maxX)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
