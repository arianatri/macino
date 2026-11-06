import AppKit

/// A single continuous outline keeps the arrow joined to the glass body.
@MainActor final class MenuBubbleView: NSView {
    static let pointerHeight: CGFloat = 10
    var pointerDistanceFromRight: CGFloat = 240 { didSet { needsLayout = true } }
    private let shapeMask = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.mask = shapeMask
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    static func outline(size: NSSize, pointerX: CGFloat) -> CGPath {
        let w = max(size.width, 1), h = max(size.height - pointerHeight, 1)
        let r = min(22, min(w, h) / 2)
        let x = min(max(pointerX, r + 12), w - r - 12)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: x + 10, y: h))
        path.addLine(to: CGPoint(x: x, y: h + pointerHeight))
        path.addLine(to: CGPoint(x: x - 10, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.path = Self.outline(size: bounds.size, pointerX: bounds.width - pointerDistanceFromRight)
        CATransaction.commit()
    }
}
