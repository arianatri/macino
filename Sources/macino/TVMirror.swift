import SwiftUI

@MainActor
final class TVMirrorModel: ObservableObject {
    static let shared = TVMirrorModel()
    @Published var devices: [DLNADevice] = []
    @Published var selectedID = ""
    @Published var status = "Find your TV on the local network."
    @Published var busy = false
    @Published var sharing = false
    @Published var audio = false
    @Published private(set) var audioAvailable = false
    @Published var profileID = "m2ts-h264"
    private let engine = MirrorEngine()

    private init() {
        audioAvailable = MirrorEngine.hasLoopbackAudio
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
            status = found.isEmpty ? "No DLNA TV found. Check Wi-Fi and TV network settings." : "Found \(found.count) TV\(found.count == 1 ? "" : "s"). Select one to share."
            busy = false
        }
    }

    func start() {
        guard let selected else { status = "Choose a TV first."; return }
        guard MirrorEngine.findFFmpeg() != nil else { status = "FFmpeg is required. Install it with Homebrew, then restart macino."; return }
        let profile = MirrorProfile.by(id: profileID)
        engine.start(device: selected, profile: profile, captureAudio: audio && audioAvailable)
    }
    func stop() { engine.stop(); sharing = false; status = "Sharing stopped." }
}

struct TVMirrorView: View {
    @StateObject private var model = TVMirrorModel.shared
    var body: some View {
        VStack(spacing: 14) {
            Card(title: "TV screen sharing", info: "Sends a live copy of your Mac display to DLNA TVs on the same network. It works with many non-Android Samsung TVs, including older models. macOS asks for Screen Recording permission when you start. FFmpeg must be installed on this Mac. System audio is optional and requires BlackHole 2ch, a separate audio driver. Video may have a few seconds of delay; protected video can appear black.") {
                HStack(spacing: 10) {
                    Image(systemName: "tv.and.mediabox.fill").font(.title2).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mirror Mac to TV").font(.headline)
                        Text("Same Wi-Fi • DLNA • No Android TV needed").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Find TVs").disabled(model.busy || model.sharing)
                }
                if !model.devices.isEmpty {
                    Picker("TV", selection: $model.selectedID) {
                        ForEach(model.devices, id: \.uuid) { Text("\($0.name) • \($0.ip)").tag($0.uuid) }
                    }.disabled(model.sharing)
                }
                Picker("Video quality", selection: $model.profileID) {
                    ForEach(MirrorProfile.all, id: \.id) { Text($0.title).tag($0.id) }
                }.disabled(model.sharing)
                Toggle("Send Mac audio to TV", isOn: $model.audio).disabled(!model.audioAvailable || model.sharing)
                if !model.audioAvailable {
                    Text("For sound, install BlackHole 2ch and select it as your Mac’s audio output. macino will then include it with the TV stream.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("BlackHole setup", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole")!)
                        .font(.caption)
                }
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
