import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let visible = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
guard visible.map(\.lastPathComponent).sorted() == ["Install with love.app"] else { fatalError("DMG must show only one installer") }
print("PASS DMG exposes one installer with its application payload inside")
func info(_ name: String) throws -> [String: Any] {
    try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent(name + "/Contents/Info.plist")), format: nil) as! [String: Any]
}
let app = try info("Install with love.app/Contents/Resources/macino.app"), installer = try info("Install with love.app")
guard app["CFBundleIdentifier"] as? String == "local.macino", installer["CFBundleIdentifier"] as? String == "local.macino.installer",
      let types = installer["CFBundleDocumentTypes"] as? [[String: Any]],
      types.contains(where: { ($0["LSItemContentTypes"] as? [String])?.contains("com.apple.application-bundle") == true }) else { fatalError("Installer identity or application drop handler is invalid") }
print("Verified signed heart installer with application drag-and-drop handler")
