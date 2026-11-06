import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
let iconset = root.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)/1024
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: s,y: s)
        let rect = NSRect(x: 40,y: 40,width: 944,height: 944)
        let shape = NSBezierPath(roundedRect: rect,xRadius: 220,yRadius: 220)
        NSGradient(colors: [NSColor(calibratedRed: 0.04,green: 0.17,blue: 0.25,alpha: 1),NSColor(calibratedRed: 0.04,green: 0.55,blue: 0.57,alpha: 1)])!.draw(in: shape,angle: 60)
        NSColor.white.withAlphaComponent(0.18).setStroke(); shape.lineWidth = 5; shape.stroke()
        let glow = NSBezierPath(ovalIn: NSRect(x: 175,y: 175,width: 674,height: 674)); NSColor.white.withAlphaComponent(0.08).setFill(); glow.fill()
        let path = NSBezierPath(); path.move(to: NSPoint(x: 220,y: 380)); path.line(to: NSPoint(x: 220,y: 590)); path.curve(to: NSPoint(x: 510,y: 590),controlPoint1: NSPoint(x: 220,y: 790),controlPoint2: NSPoint(x: 510,y: 790)); path.line(to: NSPoint(x: 510,y: 380)); path.line(to: NSPoint(x: 510,y: 590)); path.curve(to: NSPoint(x: 800,y: 590),controlPoint1: NSPoint(x: 510,y: 790),controlPoint2: NSPoint(x: 800,y: 790)); path.line(to: NSPoint(x: 800,y: 380))
        path.lineWidth = 66; path.lineCapStyle = .round; path.lineJoinStyle = .round
        NSColor(calibratedRed: 0.82,green: 1,blue: 0.95,alpha: 1).setStroke(); path.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let menu = """
<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22"><path d="M3 15V9a4 4 0 0 1 8 0v6-6a4 4 0 0 1 8 0v6" fill="none" stroke="black" stroke-width="2" stroke-linecap="round"/></svg>
"""
try menu.write(to: root.appendingPathComponent("MenuBarTemplate.svg"), atomically: true, encoding: .utf8)
