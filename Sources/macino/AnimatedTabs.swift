import SwiftUI

struct AnimatedTabs: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight
    @State private var hovered: String?
    private let tabs = ["System", "Processes", "Quick Access", "Internet", "Android", "Reader", "Clipboard"]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tabs, id: \.self) { tab in
                let selected = selection == tab
                Button { selection = tab } label: {
                    Text(tab)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .scaleEffect(selected || reduceMotion ? 1 : 0.97)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .background {
                    if selected {
                        if reduceMotion {
                            selectionPill
                        } else {
                            selectionPill.matchedGeometryEffect(id: "active-tab", in: highlight)
                        }
                    } else if hovered == tab {
                        RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.04))
                    }
                }
                .onHover { inside in hovered = inside ? tab : (hovered == tab ? nil : hovered) }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint("Show \(tab) tab")
            }
        }
        .padding(4)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.78), value: selection)
        .animation(.easeOut(duration: 0.14), value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
        .onMoveCommand { direction in
            guard let current = tabs.firstIndex(of: selection) else { return }
            if direction == .right { selection = tabs[min(current + 1, tabs.count - 1)] }
            if direction == .left { selection = tabs[max(current - 1, 0)] }
        }
    }

    private var selectionPill: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [.teal.opacity(0.24), .teal.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .shadow(color: .black.opacity(0.09), radius: 3, x: 0, y: 2)
    }
}
