import SwiftUI
import UniformTypeIdentifiers

struct ReaderView: View {
    @ObservedObject var reader: ReaderModel
    @State private var targeted = false
    @State private var editing = false
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reader.filename.isEmpty ? "Offline Reader" : reader.filename).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text("فارسی + English • Offline").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { reader.stop(); editing.toggle() } label: { Label(editing ? "Preview" : "Type text", systemImage: editing ? "doc.text" : "square.and.pencil") }.controlSize(.small)
                Button { reader.choose() } label: { Image(systemName: "doc.badge.plus") }.help("Open TXT, text PDF, DOCX or DOC")
                if !reader.filename.isEmpty || reader.state == .importing {
                    Button { reader.closeDocument() } label: { Image(systemName: "xmark") }.help("Close document")
                }
                InfoButton(title: "Offline Reader", text: "Write, paste or drop a document to listen offline. Persian and English voices switch automatically. Use text PDFs, TXT or Word files; scanned pages aren’t supported. Voices load only when you start reading and are released after each passage. This tab stays open while you work elsewhere. Press Escape or click the menu bar icon to close it.")
            }
            if editing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type or paste Persian and English text").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $reader.draftText)
                        .font(.system(size: 14)).scrollContentBackground(.hidden)
                        .padding(8).frame(height: 160)
                        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.teal.opacity(0.25)))
                        .accessibilityLabel("Text to read offline")
                    HStack {
                        Text("Your text stays on this Mac.").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button { if reader.loadTypedText() { editing = false; reader.play() } } label: {
                            Label("Read text", systemImage: "play.fill")
                        }.buttonStyle(.borderedProminent).tint(.teal)
                            .disabled(reader.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else if reader.sentences.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: targeted ? "doc.badge.arrow.up" : "doc.text").font(.system(size: 32, weight: .light)).foregroundStyle(.teal)
                    Text("Drop a document here").font(.headline)
                    Text("TXT · PDF · Word").font(.caption).foregroundStyle(.secondary)
                    Button("Choose file…") { reader.choose() }.controlSize(.small)
                }.frame(maxWidth: .infinity).frame(height: 180)
                    .background(.teal.opacity(targeted ? 0.12 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.teal.opacity(targeted ? 0.65 : 0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(reader.sentences) { sentence in
                                Button { reader.play(at: sentence.id) } label: {
                                    Text(sentence.text).font(.system(size: 14)).lineSpacing(5)
                                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 11).padding(.vertical, 7)
                                        .background(reader.currentSentence == sentence.id ? Color.teal.opacity(0.17) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                        .overlay(alignment: .leading) {
                                            if reader.currentSentence == sentence.id { Capsule().fill(.teal).frame(width: 3).padding(.vertical, 6) }
                                        }
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).id(sentence.id)
                                    .help("Read from this sentence")
                            }
                        }.padding(6)
                    }.frame(height: 190)
                        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Color.teal.opacity(0.6) : Color.primary.opacity(0.06)))
                        .onChange(of: reader.currentSentence) { _, index in
                            if let index { withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo(index, anchor: .center) } }
                        }
                }
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if reader.state == .generating || reader.state == .importing { ProgressView().controlSize(.mini) }
                    else { Circle().fill(reader.state == .playing ? .teal : .secondary.opacity(0.4)).frame(width: 5, height: 5) }
                    Text(reader.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let index = reader.currentSentence { Text("\(index + 1) / \(reader.sentences.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                }
                ProgressView(value: reader.progress).tint(.teal)
                HStack(spacing: 10) {
                    Button { reader.active ? reader.pause() : reader.play() } label: {
                        Label(reader.active ? "Pause" : (reader.state == .paused ? "Resume" : "Play"), systemImage: reader.active ? "pause.fill" : "play.fill")
                            .frame(minWidth: 82)
                    }.buttonStyle(.borderedProminent).tint(.teal).disabled(editing || !reader.canPlay)
                    Button { reader.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                        .disabled(!reader.active && reader.state != .paused)
                    Spacer()
                    Image(systemName: "pin.fill").foregroundStyle(.teal)
                    Text("Keep reading").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 7) {
                HStack {
                    Label("Speed", systemImage: "speedometer").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(String(format: "%.2f×", reader.speed)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.teal).padding(.horizontal, 9).padding(.vertical, 4).background(.teal.opacity(0.09), in: Capsule())
                }
                HStack(spacing: 10) {
                    Image(systemName: "tortoise").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { ReaderSpeedScale.position(for: reader.speed) }, set: { reader.speed = (ReaderSpeedScale.speed(at: $0) * 20).rounded() / 20 }), in: 0...1).tint(.teal).accessibilityLabel("Reading speed").accessibilityValue(String(format: "%g times", reader.speed))
                    Image(systemName: "hare").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("0.5×").frame(maxWidth: .infinity, alignment: .leading)
                    Text("1×").frame(maxWidth: .infinity)
                    Text("2×").frame(maxWidth: .infinity, alignment: .trailing)
                }.font(.caption2).foregroundStyle(.secondary)

            }.padding(12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        }
        .contentShape(Rectangle())
        .onChange(of: reader.state) { _, state in if state == .importing { editing = false } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            guard providers.count == 1, let provider = providers.first else { reader.message = "Drop one document at a time."; return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                let url: URL?
                if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = value as? URL }
                Task { @MainActor in
                    if let url { reader.load(url) }
                    else { reader.message = error?.localizedDescription ?? "This drop did not contain a document file." }
                }
            }
            return true
        }
    }
}
