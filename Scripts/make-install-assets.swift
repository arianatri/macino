import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

func render(_ size: NSSize, _ draw: () -> Void) -> NSImage {
    let image = NSImage(size: size); image.lockFocus(); draw(); image.unlockFocus(); return image
}
func writePNG(_ image: NSImage, _ url: URL) throws {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
func text(_ value: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
    (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let ink = NSColor(calibratedRed: 0.07, green: 0.23, blue: 0.27, alpha: 1)
let background = render(NSSize(width: 1440, height: 960)) {
    NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)
    let bounds = NSRect(x: 0, y: 0, width: 720, height: 480)
    NSGradient(colors: [NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.95, green: 0.90, blue: 0.96, alpha: 1)])!.draw(in: bounds, angle: 25)
    let panel = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 664, height: 424), xRadius: 32, yRadius: 32)
    NSColor.white.withAlphaComponent(0.48).setFill(); panel.fill()
    text("macino", at: NSPoint(x: 54, y: 412), size: 16, weight: .bold, color: NSColor.systemTeal)
    text("Created by Arian Atri", at: NSPoint(x: 487, y: 412), size: 13, weight: .semibold, color: ink)
    text("A little love for your Mac.", at: NSPoint(x: 54, y: 356), size: 31, weight: .bold, color: ink)
    text("Drag macino into Applications to install.", at: NSPoint(x: 55, y: 325), size: 16, color: ink.withAlphaComponent(0.7))
    text("♥", at: NSPoint(x: 367, y: 313), size: 38, weight: .bold,
         color: NSColor(calibratedRed: 0.91, green: 0.08, blue: 0.18, alpha: 1))
    for x: CGFloat in [100, 440] {
        let tile = NSBezierPath(roundedRect: NSRect(x: x, y: 139, width: 180, height: 170), xRadius: 30, yRadius: 30)
        NSColor.white.withAlphaComponent(0.65).setFill(); tile.fill()
    }
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 315, y: 230)); arrow.line(to: NSPoint(x: 405, y: 230))
    arrow.move(to: NSPoint(x: 394, y: 241)); arrow.line(to: NSPoint(x: 405, y: 230)); arrow.line(to: NSPoint(x: 394, y: 219))
    arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    NSColor.systemTeal.setStroke(); arrow.stroke()
    text("Then open macino from Applications.", at: NSPoint(x: 217, y: 91), size: 15, weight: .medium, color: ink)
    text("One app. No separate installer.", at: NSPoint(x: 274, y: 65), size: 12, color: ink.withAlphaComponent(0.6))
}
try writePNG(background, root.appendingPathComponent("installer@2x.png"))
// Use a TIFF with explicit logical size so Finder renders the retina art at 720 × 480.
let logical = NSImage(size: NSSize(width: 720, height: 480))
let rep = NSBitmapImageRep(data: background.tiffRepresentation!)!; rep.size = NSSize(width: 720,height: 480); logical.addRepresentation(rep)
try rep.tiffRepresentation(using: .lzw, factor: 1)!.write(to: root.appendingPathComponent("installer.tiff"))
let heart = render(NSSize(width: 512, height: 512)) {
    let shape = NSBezierPath()
    shape.move(to: NSPoint(x: 256, y: 61))
    shape.curve(to: NSPoint(x: 57,y: 262),controlPoint1: NSPoint(x: 222,y: 94),controlPoint2: NSPoint(x: 57,y: 191))
    shape.curve(to: NSPoint(x: 256,y: 392),controlPoint1: NSPoint(x: 21,y: 411),controlPoint2: NSPoint(x: 169,y: 485))
    shape.curve(to: NSPoint(x: 455,y: 262),controlPoint1: NSPoint(x: 343,y: 485),controlPoint2: NSPoint(x: 491,y: 411))
    shape.curve(to: NSPoint(x: 256,y: 61),controlPoint1: NSPoint(x: 455,y: 191),controlPoint2: NSPoint(x: 290,y: 94))
    shape.close()
    NSGradient(colors: [NSColor(calibratedRed: 0.84,green: 0.13,blue: 0.39,alpha: 1), NSColor(calibratedRed: 1,green: 0.47,blue: 0.64,alpha: 1)])!.draw(in: shape,angle: 65)
    NSColor.white.withAlphaComponent(0.8).setStroke(); shape.lineWidth = 5; shape.stroke()
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 256,y: 335)); arrow.line(to: NSPoint(x: 256,y: 190)); arrow.move(to: NSPoint(x: 200,y: 245)); arrow.line(to: NSPoint(x: 256,y: 189)); arrow.line(to: NSPoint(x: 312,y: 245)); arrow.lineWidth = 23; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; NSColor.white.setStroke(); arrow.stroke()
}
try writePNG(heart, root.appendingPathComponent("InstallHeart.png"))
print("Generated retina installer art and heart icon")
