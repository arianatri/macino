import SwiftUI
import AppKit

struct AndroidView: View {
    @ObservedObject var model: AndroidModel
    @ObservedObject private var screen = AndroidScreenSession.shared
    var body: some View {
        VStack(spacing: 14) {
            Card(title: "File transfer", info: "Connect your phone with a USB data cable, unlock it and choose File transfer on the phone. Close any other MTP app first. Browse files here, then send or download one at a time. Existing files won’t be replaced. Keep the phone connected until the transfer finishes. USB debugging isn’t needed for file transfer.") {
                HStack {
                    Image(systemName: "cable.connector").font(.title2).foregroundStyle(.teal)
                    Text("USB / MTP").font(.headline)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button { model.scan() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh USB phones").disabled(model.busy)
                }
                if !model.devices.isEmpty {
                    HStack {
                        Picker("Phone", selection: $model.selectedDevice) {
                            ForEach(model.devices) { device in Text(device.name.isEmpty ? "Android \(device.id)" : device.name).tag(device.id) }
                        }.labelsHidden().onChange(of: model.selectedDevice) { _, _ in model.resetConnection() }
                        Button("Connect") { model.connect() }.buttonStyle(.borderedProminent).tint(.teal)
                    }.disabled(model.busy)
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if model.connected {
                    Divider()
                    Picker("Storage", selection: $model.selectedStorage) {
                        ForEach(model.storages) { storage in
                            Text(storage.name.isEmpty ? "Storage \(storage.id)" : storage.name).tag(storage.id)
                        }
                    }.onChange(of: model.selectedStorage) { old, new in
                        if old != 0 && new != 0 { model.browse(storageChanged: true) }
                    }.disabled(model.busy)
                    if let storage = model.storages.first(where: { $0.id == model.selectedStorage }) {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(clamping: storage.free), countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: Int64(clamping: storage.capacity), countStyle: .file))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button { model.browse(up: true) } label: { Image(systemName: "arrow.up") }.disabled(model.folders.isEmpty || model.busy).help("Parent folder")
                        Text(model.path).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { model.browse() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh files")
                        Button { model.upload() } label: { Label("Send", systemImage: "arrow.up.doc") }.help("Send a file to this folder")
                    }.disabled(model.busy)
                    if model.files.isEmpty && !model.busy {
                        Text("This folder is empty.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(model.files) { file in
                            HStack(spacing: 9) {
                                Image(systemName: file.folder ? "folder.fill" : "doc").foregroundStyle(file.folder ? Color.teal : Color.secondary).frame(width: 18)
                                Button { if file.folder { model.browse(file) } else { model.download(file) } } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name).lineLimit(1).truncationMode(.middle).font(.system(size: 12, weight: file.folder ? .medium : .regular))
                                        if !file.folder { Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: file.size), countStyle: .file)).font(.caption2).foregroundStyle(.secondary) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Image(systemName: file.folder ? "chevron.right" : "arrow.down.circle").foregroundStyle(.secondary).font(.caption)
                            }.padding(.vertical, 9)
                            Divider().opacity(0.4)
                        }
                    }.disabled(model.busy)
                }
            }
            Card(title: "Screen sharing", info: "Shows your phone screen in a separate macino window using scrcpy. On the phone, enable Developer options → USB debugging, connect USB, then approve the RSA prompt. Tap Refresh and select the authorized phone. Android 5.0 or later is required. Sharing is view-only, with audio and clipboard sync off. The screen stops when you close its window, press Stop, or quit macino. This is local mirroring, not a video-call broadcast. For Wi-Fi on Android 11+, connect both devices to the same network and enable Wireless debugging on the phone. Open Pair device with pairing code; use its IP, pairing port and six-digit code here. Then use the separate connection port on the main Wireless debugging page. After pairing, Connect and Share screen. Disconnect ends the network connection; to revoke trust, choose Forget on the phone. macino never enables debugging or approves trust automatically.") {
                HStack {
                    Label("Android screen", systemImage: "rectangle.on.rectangle").font(.headline)
                    Spacer()
                    if model.screenBusy { ProgressView().controlSize(.small) }
                    Button { model.refreshScreens() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh screen-sharing phones").disabled(model.screenBusy || screen.running)
                }
                Picker("Connection", selection: $model.screenWiFi) {
                    Text("USB").tag(false)
                    Text("Wi-Fi").tag(true)
                }.pickerStyle(.segmented).disabled(screen.running || model.screenBusy)
                    .onChange(of: model.screenWiFi) { _, _ in model.selectScreenTransport(); model.refreshScreens() }
                if model.screenWiFi { wifiControls }
                if !model.visibleScreens.isEmpty {
                    Picker("Phone", selection: $model.selectedScreen) {
                        ForEach(model.visibleScreens) { device in Text("\(device.name) • \(device.authorized ? "Ready" : device.state)").tag(device.id) }
                    }.disabled(screen.running)
                }
                Text(screen.running ? "Sharing in a separate window • View only" : model.screenStatus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    if screen.running {
                        Button("Stop sharing", role: .destructive) { screen.stop() }
                    } else {
                        Button { screen.start(serial: model.selectedScreen) } label: { Label("Share screen", systemImage: "play.rectangle") }
                            .buttonStyle(.borderedProminent).tint(.teal)
                            .disabled(!model.selectedReady || model.screenBusy)
                    }
                    Spacer()
                    Text(model.screenWiFi ? "Local • Wi-Fi" : "Local • USB").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.firstScan() }

    }
    private var wifiControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Same Wi-Fi • Wireless debugging • Android 11+").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Phone IP", text: $model.wifiHost).frame(maxWidth: .infinity)
                TextField("Connect port", text: $model.wifiPort).frame(width: 110)
            }.textFieldStyle(.roundedBorder)
            HStack {
                Button("Connect") { model.connectWiFi() }
                Button("Disconnect") { model.disconnectWiFi() }.disabled(!model.selectedReady)
                Spacer()
            }.controlSize(.small)
            DisclosureGroup("Pair a new phone") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On your phone: Wireless debugging → Pair device with pairing code.").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Pairing port", text: $model.pairingPort)
                        SecureField("6-digit code", text: $model.pairingCode)
                        Button("Pair") { model.pairWiFi() }
                    }.textFieldStyle(.roundedBorder).controlSize(.small)
                    Text("Pair first, then enter the separate connection port above.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.font(.callout)
        }.disabled(model.screenBusy || screen.running)
    }

}
