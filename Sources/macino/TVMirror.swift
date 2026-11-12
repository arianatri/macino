import SwiftUI

@MainActor
final class TVMirrorModel: ObservableObject {
    static let shared = TVMirrorModel()
    @Published var devices: [DLNADevice] = []
    @Published var selectedID = ""
    @Published var status = "Choose a TV to start sharing."
    @Published var busy = false
    @Published var sharing = false
    @Published var audio = true
    @Published var profileID = "m2ts-h264"
    private let engine = MirrorEngine()

    private init() {
        engine.onState = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle: self.sharing = false; self.status = "Sharing stopped."
            case .preparing(let message): self.sharing = true; self.status = message
            case .mirroring(let name): self.sharing = true; self.status = "Sharing to \(name)."
            case .failed(let message): self.sharing = false; self.status = message
            }
        }
    }

    var selected: DLNADevice? { devices.first { $0.uuid == selectedID } }
    func refresh() {
        guard !busy else { return }
        busy = true; status = "Searching for TVs…"
        Task {
            let found = await Task.detached(priority: .userInitiated) { SSDP.discover(timeout: 3) }.value
            devices = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !devices.contains(where: { $0.uuid == selectedID }) { selectedID = devices.first?.uuid ?? "" }
            if found.isEmpty {
                status = "No compatible TV found. Check that your TV supports DLNA and both devices are on the same Wi-Fi, then search again."
            } else {
                let tvLabel = found.count == 1 ? "TV" : "TVs"
                let prompt = found.count == 1 ? "Choose it to start sharing." : "Choose one to start sharing."
                status = "Found \(found.count) compatible \(tvLabel). \(prompt)"
            }
            busy = false
        }
    }

    func start() {
        guard let selected else { status = "Choose a TV before you start."; return }
        guard MirrorEngine.findFFmpeg() != nil else {
            status = "TV sharing needs FFmpeg. Install it with Homebrew, then reopen macino."
            return
        }
        let profile = MirrorProfile.by(id: profileID)
        engine.start(device: selected, profile: profile, captureAudio: audio)
    }
    func stop() { engine.stop(); sharing = false; status = "Sharing stopped." }
}

struct TVMirrorView: View {
    @StateObject private var model = TVMirrorModel.shared
    var body: some View {
        VStack(spacing: 14) {
            Card(title: "TV screen sharing", info: "Share your screen and optional system audio with a compatible DLNA TV on the same Wi-Fi. You'll need FFmpeg and Screen Recording access. macino captures system audio without an extra driver or changing your Mac's sound output. Protected content may appear black, and playback may have a short delay.") {
                HStack(spacing: 10) {
                    Image(systemName: "tv.and.mediabox.fill").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mirror your Mac to a TV").font(.headline)
                        Text("Works with DLNA TVs over Wi-Fi—no Android TV required").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Search for TVs again").disabled(model.busy || model.sharing)
                }
                if !model.devices.isEmpty {
                    Picker("TV", selection: $model.selectedID) {
                        ForEach(model.devices, id: \.uuid) { Text("\($0.name) • \($0.ip)").tag($0.uuid) }
                    }.disabled(model.sharing)
                }
                Picker("Video format", selection: $model.profileID) {
                    ForEach(MirrorProfile.all, id: \.id) { Text($0.title).tag($0.id) }
                }.disabled(model.sharing)
                Toggle("Send system audio to TV", isOn: $model.audio).disabled(model.sharing)
                Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    if model.sharing { Button("Stop sharing", role: .destructive) { model.stop() } }
                    else { Button { model.start() } label: { Label("Start sharing", systemImage: "play.rectangle") }.buttonStyle(.borderedProminent).tint(.teal).disabled(model.selected == nil || model.busy) }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
            }
        }.onAppear { if model.devices.isEmpty { model.refresh() } }
    }
}
