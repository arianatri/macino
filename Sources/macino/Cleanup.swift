import Foundation
struct CacheCategory: Identifiable {
    let id: String; let title: String; let url: URL; var size: UInt64 = 0; var files = 0
}
enum Cleanup {
    // Deliberately narrow allowlist: no browser, account, credential, or preference stores.
    static var categories: [CacheCategory] {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return [("macino", "macino cache", "local.macino"), ("quicklook", "Quick Look thumbnails", "com.apple.QuickLook.thumbnailcache")].map { CacheCategory(id: $0.0, title: $0.1, url: base.appendingPathComponent($0.2)) }
    }
    static func regularFiles(_ root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        let rootInfo = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootInfo.isSymbolicLink != true, rootInfo.isDirectory == true else { throw AppError.message("Skipped unsafe cache path: \(root.path)") }
        var failure: Error?
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [], errorHandler: { _, error in failure = error; return false }) else { return [] }
        var files: [URL] = []
        for case let url as URL in e {
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if v.isSymbolicLink == true { e.skipDescendants(); continue }
            if v.isRegularFile == true { files.append(url) }
        }
        if let failure { throw failure }; return files
    }
    static func scan() throws -> [CacheCategory] {
        try categories.map { category in var c = category; let files = try regularFiles(c.url); c.files = files.count; c.size = try files.reduce(0) { sum, url in let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]); return sum + UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) }; return c }
    }
    static func clear(_ ids: Set<String>, within permitted: [CacheCategory] = categories) -> String {
        var removed: UInt64 = 0; var count = 0; var failures: [String] = []
        for category in permitted where ids.contains(category.id) {
            do { for url in try regularFiles(category.url) {
                do {
                    // Recheck each ancestor immediately before removal; never traverse symlinks.
                    var parent = url.deletingLastPathComponent()
                    while parent.path.hasPrefix(category.url.path) { if try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw AppError.message("Path changed to a symbolic link") }; if parent == category.url { break }; parent.deleteLastPathComponent() }
                    let v = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]); guard v.isSymbolicLink != true else { continue }
                    let size = UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                    try FileManager.default.removeItem(at: url); removed += size; count += 1
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            } } catch { failures.append(error.localizedDescription) }
        }
        return "Removed \(count) files (\(bytes(removed)) allocated bytes). APFS snapshots and open files can delay physical recovery." + (failures.isEmpty ? "" : "\nSkipped/failed: " + failures.prefix(8).joined(separator: "\n"))
    }
}
