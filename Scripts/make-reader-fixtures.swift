import AppKit
import PDFKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for (name, text) in [("text.pdf", "Offline PDF test. Hello from macino."), ("scanned.pdf", "")] {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError("Cannot create PDF fixture") }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    (text as NSString).draw(at: NSPoint(x: 40, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage(); context.closePDF()
    try (data as Data).write(to: root.appendingPathComponent(name))
}
