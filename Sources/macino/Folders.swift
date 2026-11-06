import AppKit
import SwiftUI

// Preserve the existing bookmark schema and preferences key for saved folders.
struct FolderBookmark: Identifiable, Codable {
    var id = UUID(); var data: Data; var originalPath: String
    func resolve() throws -> (URL, Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}
@MainActor final class FolderStore: ObservableObject {
    @Published var folders: [FolderBookmark] = []
    @Published var error: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "folders") { folders = (try? JSONDecoder().decode([FolderBookmark].self, from: data)) ?? [] }
    }
    func save() { if let data = try? JSONEncoder().encode(folders) { defaults.set(data, forKey: "folders") } }
    func choose(replacing id: UUID? = nil, files: Bool = false) {
        let picker = NSOpenPanel()
        picker.canChooseFiles = files || id != nil
        picker.canChooseDirectories = !files || id != nil
        picker.allowsMultipleSelection = id == nil
        picker.title = id != nil ? "Relink shortcut" : (files ? "Add files to Quick Access" : "Add folders to Quick Access")
        picker.prompt = id != nil ? "Relink" : "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK else { return }
        do { try add(picker.urls, replacing: id) } catch { self.error = error.localizedDescription }
    }
    func add(_ urls: [URL], replacing id: UUID? = nil) throws {
        var updated = folders
        for url in urls {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            let duplicate = updated.contains { $0.id != id && URL(fileURLWithPath: $0.originalPath).resolvingSymlinksInPath().standardizedFileURL.path == path }
            if duplicate { continue }
            var item = FolderBookmark(data: try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), originalPath: url.path)
            if let id, let index = updated.firstIndex(where: { $0.id == id }) { item.id = id; updated[index] = item }
            else { updated.append(item) }
        }
        folders = updated; save()
    }
    func open(_ item: FolderBookmark) {
        do {
            let (url, stale) = try item.resolve()
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw AppError.message("Item unavailable. Use Relink to choose it again.") }
            if stale, let index = folders.firstIndex(where: { $0.id == item.id }) {
                folders[index].data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                folders[index].originalPath = url.path; save()
            }
            guard NSWorkspace.shared.open(url) else { throw AppError.message("macOS could not open this item. Check its default application in Finder.") }
        } catch { self.error = error.localizedDescription }
    }
    func reveal(_ item: FolderBookmark) {
        do { NSWorkspace.shared.activateFileViewerSelecting([try item.resolve().0]) }
        catch { self.error = error.localizedDescription }
    }
    func move(_ id: UUID, by delta: Int) {
        guard let index = folders.firstIndex(where: { $0.id == id }), folders.indices.contains(index + delta) else { return }
        folders.swapAt(index, index + delta); save()
    }
}
