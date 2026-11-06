import SwiftUI
import AppKit

struct AppearanceSurface<Content: View>: View {
    let content: Content
    @AppStorage("appearance.followSystem") private var followSystem = true
    @AppStorage("appearance.transparency") private var transparency = 0.65
    @AppStorage("appearance.textContrast") private var textContrast = 0.5
    var body: some View {
        content
            .contrast(followSystem ? 1 : 0.8 + min(max(textContrast, 0), 1) * 0.8)
            .background {
                if !followSystem {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(1 - min(max(transparency, 0), 1))
                        .allowsHitTesting(false)
                }
            }
    }
}
struct AppearanceSettings: View {
    @AppStorage("appearance.followSystem") private var followSystem = true
    @AppStorage("appearance.transparency") private var transparency = 0.65
    @AppStorage("appearance.textContrast") private var textContrast = 0.5
    var body: some View {
        Card(title: "Appearance", info: "Use your Mac’s appearance, or turn this off to adjust it yourself. More transparency shows more of the background. Increase text contrast to make text easier to read. Reduce Transparency in macOS can override the glass effect.") {
            Toggle("Use Mac appearance", isOn: $followSystem).toggleStyle(.checkbox)
            if !followSystem {
                VStack(spacing: 12) {
                    HStack {
                        Label("Transparency", systemImage: "square.on.square")
                        Slider(value: $transparency, in: 0...1).labelsHidden().accessibilityLabel("Transparency")
                        Text(transparency, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 40)
                    }
                    HStack {
                        Label("Text contrast", systemImage: "textformat")
                        Slider(value: $textContrast, in: 0...1).labelsHidden().accessibilityLabel("Text contrast")
                        Text(textContrast, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 40)
                    }
                    HStack { Spacer(); Button("Restore Defaults") { transparency = 0.65; textContrast = 0.5; followSystem = true } }
                }.font(.callout)
            }
        }
    }
}
