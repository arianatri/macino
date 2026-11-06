import AppKit
import SwiftUI

/// Put the entire SwiftUI surface inside Apple's native glass compositor.
/// Cards use light fills so they do not mask the glass with opaque material layers.
@MainActor final class GlassHostingController<Content: View>: NSViewController {
    private let root: Content
    private let useLegacyMaterial: Bool
    private let menuBubble: Bool
    init(rootView: Content, useLegacyMaterial: Bool = false, menuBubble: Bool = false) { root = rootView; self.useLegacyMaterial = useLegacyMaterial; self.menuBubble = menuBubble; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func loadView() {
        let host = NSHostingView(rootView: AppearanceSurface(content: root))
        host.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *), !useLegacyMaterial {
            let surface = NSView()
            surface.wantsLayer = true
            surface.layer?.cornerRadius = 22
            surface.layer?.masksToBounds = true
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 26
            glass.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.addSubview(host)
            glass.contentView = content
            surface.addSubview(glass)
            // Crop the native glass rim outside the visible surface, retaining its live compositor.
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: -6),
                glass.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: 6),
                glass.topAnchor.constraint(equalTo: surface.topAnchor, constant: -6),
                glass.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: 6)
            ])
            view = surface
        } else {
            let material = NSVisualEffectView()
            material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
            material.wantsLayer = true; material.layer?.cornerRadius = 22; material.layer?.masksToBounds = true
            material.addSubview(host); view = material
        }
        if menuBubble {
            let background = view
            let bubble = MenuBubbleView(frame: .zero)
            view = bubble
            background.translatesAutoresizingMaskIntoConstraints = false
            bubble.addSubview(background)
            NSLayoutConstraint.activate([
                background.leadingAnchor.constraint(equalTo: bubble.leadingAnchor), background.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
                background.topAnchor.constraint(equalTo: bubble.topAnchor), background.bottomAnchor.constraint(equalTo: bubble.bottomAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor, constant: menuBubble ? MenuBubbleView.pointerHeight : 0), host.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
