import SwiftUI
import AppKit

/// Navigates filesystem paths only; input is never executed as a shell command.
enum PathNavigator {
    static func expanded(_ input: String) throws -> String {
        let path = (input as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { throw AppError.message("Enter an absolute path starting with / or ~/.") }
        return (path as NSString).standardizingPath
    }
    static func destination(_ input: String) throws -> (url: URL, directory: Bool) {
        let path = try expanded(input)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else { throw AppError.message("This path does not exist or is inaccessible. Mac home folders are under /Users, for example /Users/arian.") }
        return (URL(fileURLWithPath: path), directory.boolValue)
    }
    static func suggestions(_ input: String) throws -> [String] {
        let raw = input.isEmpty ? "~/" : (input as NSString).expandingTildeInPath
        let path = (raw as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return [] }
        let parent = path.hasSuffix("/") ? path : (path as NSString).deletingLastPathComponent
        let prefix = path.hasSuffix("/") ? "" : (path as NSString).lastPathComponent
        return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: parent), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (prefix.isEmpty || $0.lastPathComponent.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil) && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(5).map { ($0.path as NSString).standardizingPath + "/" }
    }
}

struct RunView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var path = ""
    @State private var suggestions: [String] = []
    @State private var error: String?
    @State private var loading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.8)) { expanded.toggle() }
                focused = expanded
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.teal)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                    Text("Run").font(.system(size: 12, weight: .semibold))
                    if !expanded { Text("Go to a path…").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).padding(10)
            }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse Run" : "Expand Run")
            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        TextField("/Users/arian or ~/Downloads", text: $path)
                            .font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder)
                            .focused($focused).onSubmit(go)
                            .accessibilityLabel("Run path")
                        Button("Go", action: go).buttonStyle(.borderedProminent).tint(.teal)
                            .disabled(path.isEmpty)
                    }
                    if let error { Text(error).font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                    if loading { ProgressView().controlSize(.mini).frame(height: 16) }
                    if !suggestions.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button { path = suggestion; focused = true } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "folder").foregroundStyle(.teal)
                                            Text(suggestion).lineLimit(1).truncationMode(.middle)
                                            Spacer(minLength: 0)
                                            Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                                        }.font(.system(size: 11)).padding(.vertical, 4).contentShape(Rectangle())
                                    }.buttonStyle(.plain).help("Complete this path, then press Go or Enter")
                                }
                            }
                        }.frame(height: CGFloat(min(suggestions.count, 3)) * 25)
                    }
                    Text("Folders open in Finder • files are revealed • Enter to go")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).padding(.bottom, 10)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
        }.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .clipped()
            .task(id: "\(expanded):\(path)") {
                guard expanded else { suggestions = []; loading = false; return }
                error = nil; loading = true
                let input = path
                do {
                    try await Task.sleep(nanoseconds: 120_000_000)
                    let result = try await Task.detached(priority: .utility) { try PathNavigator.suggestions(input) }.value
                    try Task.checkCancellation()
                    suggestions = result; loading = false
                } catch is CancellationError { /* A newer query owns the state. */ }
                catch { guard !Task.isCancelled else { return }; suggestions = []; loading = false }
            }
    }
    private func go() {
        do {
            let target = try PathNavigator.destination(path)
            if target.directory {
                guard NSWorkspace.shared.open(target.url) else { throw AppError.message("Finder could not open this folder.") }
            } else { NSWorkspace.shared.activateFileViewerSelecting([target.url]) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
