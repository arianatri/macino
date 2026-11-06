import AppKit

/// Draw the menu metrics in pairs: top-to-bottom, then left-to-right.
/// A template image keeps both rows legible in light/dark and selected menus.
enum MenuMetricsImage {
    static func columns(_ selection: Set<MenuMetric>) -> [[MenuMetric]] {
        let values = MenuMetric.selected(selection)
        return stride(from: 0, to: values.count, by: 2).map { start in
            Array(values[start..<min(start + 2, values.count)])
        }
    }
    static func make(icon: NSImage, snapshot: SystemSnapshot, selection: Set<MenuMetric>) -> NSImage {
        let columns = columns(selection)
        guard !columns.isEmpty else { return icon }
        let single = selection.count == 1
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: single ? 10 : 8, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let labels = columns.map { column in column.map { NSAttributedString(string: "\($0.label) \($0.value(in: snapshot))", attributes: attributes) } }
        let widths = labels.map { ceil($0.map { $0.size().width }.max() ?? 0) }
        let width = 15 + widths.reduce(0, +) + CGFloat(max(0, columns.count - 1)) * 2
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: 4, width: 13, height: 13))
            var x: CGFloat = 15
            for (index, column) in labels.enumerated() {
                for (row, label) in column.enumerated() {
                    let y: CGFloat = single ? floor((22 - label.size().height) / 2) : (row == 0 ? 11 : 2)
                    label.draw(at: NSPoint(x: x, y: y))
                }
                x += widths[index] + 2
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
