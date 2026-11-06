import SwiftUI
import AppKit

struct FolderShortcutRow: View {
    let folder: FolderBookmark
    @ObservedObject var store: FolderStore
    @State private var hovered = false
    private var url: URL? { try? folder.resolve().0 }
    private var available: Bool { url.map { FileManager.default.isReadableFile(atPath: $0.path) } ?? false }
    private var name: String { (url ?? URL(fileURLWithPath: folder.originalPath)).lastPathComponent }
    var body: some View {
        HStack(spacing: 10) {
            Button { store.open(folder) } label: {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url?.path ?? folder.originalPath))
                        .resizable().frame(width: 24, height: 24)
                        .padding(4).background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(available ? (url?.path ?? folder.originalPath) : "Unavailable • Relink item")
                            .font(.system(size: 10)).foregroundStyle(available ? Color.secondary : Color.orange)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: available ? "arrow.up.right" : "exclamationmark.circle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(hovered ? Color.teal : Color.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(url?.path ?? folder.originalPath)
            Menu {
                Button("Open", systemImage: "arrow.up.right") { store.open(folder) }
                Button("Show in Finder", systemImage: "folder") { store.reveal(folder) }
                Divider()
                Button("Move up", systemImage: "arrow.up") { store.move(folder.id, by: -1) }.disabled(store.folders.first?.id == folder.id)
                Button("Move down", systemImage: "arrow.down") { store.move(folder.id, by: 1) }.disabled(store.folders.last?.id == folder.id)
                Button("Relink…", systemImage: "link") { store.choose(replacing: folder.id) }
                Divider()
                Button("Remove shortcut", systemImage: "trash", role: .destructive) {
                    store.folders.removeAll { $0.id == folder.id }; store.save()
                }
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 26) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Options for \(name)")
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .background(.primary.opacity(hovered ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(hovered ? Color.teal.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
