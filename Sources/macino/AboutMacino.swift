import AppKit

@MainActor enum AboutMacino {
    static let author = "Arian Atri"
    static let profile = URL(string: "https://github.com/ArianAtri")!
    static let profileLabel = "github.com/ArianAtri"

    static func present() {
        let credits = NSMutableAttributedString(string: "Created by \(author)\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        credits.append(NSAttributedString(string: profileLabel, attributes: [.link: profile, .foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 13)]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "macino", .credits: credits])
    }
}
