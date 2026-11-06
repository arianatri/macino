import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor final class ReaderModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ReaderModel()
    enum State { case idle, importing, generating, playing, paused, finished }
    @Published private(set) var state: State = .idle
    @Published private(set) var sentences: [ReaderSentence] = []
    @Published private(set) var filename = ""
    @Published private(set) var currentSentence: Int?
    @Published var draftText = ""
    @Published var message: String?
    @Published var speed = 1.0 {
        didSet {
            let clamped = speed.isFinite ? min(2, max(0.5, speed)) : 1
            if speed != clamped { speed = clamped; return }
            player?.rate = Float(speed)
            defaults.set(speed, forKey: "readerSpeechRate")
        }
    }
    private let defaults: UserDefaults
    var playbackVolume: Float = 1
    var voiceProcessID: Int32? { worker?.processIdentifier }
    var hasPlaybackResources: Bool { worker != nil || player != nil || work != nil }
    private var worker: ReaderTaskProcess?
    private var importer: ReaderTaskProcess?
    private var pipeline: Task<Void, Never>?
    private var session = UUID()
    private var importSession = UUID()
    private var work: URL?
    private var player: AVAudioPlayer?
    private var playback: CheckedContinuation<Bool, Never>?
    private var sentenceIndex = 0
    private var partIndex = 0
    var active: Bool { state == .playing || state == .generating }
    var canPlay: Bool { !sentences.isEmpty && state != .importing }
    var progress: Double { sentences.isEmpty ? 0 : (state == .finished ? 1 : Double(currentSentence ?? sentenceIndex) / Double(sentences.count)) }
    var status: String {
        switch state {
        case .idle: return sentences.isEmpty ? "Add a document or write something to begin" : "Ready to read"
        case .importing: return "Opening your document…"
        case .generating: return "Getting the next passage ready…"
        case .playing: return "Reading aloud"
        case .paused: return "Paused"
        case .finished: return "Finished reading"
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        let saved = defaults.double(forKey: "readerSpeechRate")
        speed = saved > 0 && saved.isFinite ? min(2, max(0.5, saved)) : 1
    }
    static var resources: URL { Bundle.main.resourceURL!.appendingPathComponent("Reader", isDirectory: true) }
    private func helper(_ name: String) throws -> URL {
        let url = Self.resources.appendingPathComponent(name)
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw AppError.message("Reader tools are missing. Install the latest macino DMG.") }
        return url
    }
    func choose() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.title = "Read a document offline"; picker.prompt = "Open"
        picker.allowedContentTypes = [.plainText, .pdf, .init(filenameExtension: "docx")!, .init(filenameExtension: "doc")!]
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK, let url = picker.url { load(url) }
    }
    func load(_ url: URL) {
        guard ReaderText.extensions.contains(url.pathExtension.lowercased()) else { message = "Drop one TXT, text PDF, DOCX or DOC file."; return }
        stop(); importer?.cancel(); importSession = UUID(); let ticket = importSession
        let process = ReaderTaskProcess(); importer = process; state = .importing
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macino-reader-import-" + UUID().uuidString)
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; try? FileManager.default.removeItem(at: directory) }
            do {
                try await process.run(helper: helper("macino-reader-import"), arguments: [], input: JSONSerialization.data(withJSONObject: ["path": url.path]), directory: directory)
                let data = try Data(contentsOf: directory.appendingPathComponent("response"))
                guard let text = (try JSONSerialization.jsonObject(with: data) as? [String: String])?["text"] else { throw AppError.message("No document text was returned.") }
                let parsed = await Task.detached(priority: .userInitiated) { ReaderText.sentences(text) }.value
                guard ticket == importSession else { return }
                guard !parsed.isEmpty && parsed.count <= 10000 else { throw AppError.message("The document is empty or has too many sentences. Split it into smaller files.") }
                sentences = parsed; filename = url.lastPathComponent; sentenceIndex = 0; partIndex = 0; currentSentence = nil
                importer = nil; state = .idle
            } catch {
                guard ticket == importSession else { return }
                importer = nil; state = .idle
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }
    @discardableResult
    func loadTypedText() -> Bool {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { message = "Type or paste some text first."; return false }
        guard text.count <= 2_000_000 else { message = "This text is too large. Split it into smaller parts."; return false }
        let parsed = ReaderText.sentences(text)
        guard !parsed.isEmpty && parsed.count <= 10000 else { message = "This text has too many sentences. Split it into smaller parts."; return false }
        stop(); importer?.cancel(); importer = nil; importSession = UUID()
        sentences = parsed; filename = "Typed text"; sentenceIndex = 0; partIndex = 0; currentSentence = nil; state = .idle
        return true
    }
    func closeDocument() {
        stop(); importer?.cancel(); importer = nil; importSession = UUID()
        sentences = []; filename = ""; draftText = ""; state = .idle
    }
    func play(at index: Int? = nil) {
        guard canPlay else { return }
        if let index {
            stop(); sentenceIndex = min(max(0, index), sentences.count - 1); partIndex = 0
        } else if state == .paused, let player {
            player.rate = Float(speed); state = .playing; player.play(); return
        } else if active { return }
        if state == .finished { sentenceIndex = 0; partIndex = 0 }
        let ticket = UUID(); session = ticket
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macino-reader-audio-" + ticket.uuidString)
        work = directory; state = .generating
        pipeline = Task {
            do {
                while sentenceIndex < sentences.count && ticket == session && !Task.isCancelled {
                    let sentence = sentences[sentenceIndex]
                    let parts = ReaderText.parts(sentence.text)
                    while partIndex < parts.count && ticket == session && !Task.isCancelled {
                        let part = parts[partIndex]
                        let unit = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                        let wave = unit.appendingPathComponent("voice.wav")
                        let process = ReaderTaskProcess(); worker = process; state = .generating
                        try await process.run(helper: helper("macino-speech"), arguments: [Self.resources.path, part.language.rawValue, wave.path], input: Data(part.text.utf8), directory: unit, timeout: 90)
                        guard ticket == session && !Task.isCancelled else { return }
                        worker = nil // the child has exited: no model remains resident
                        let audio = try AVAudioPlayer(contentsOf: wave)
                        audio.enableRate = true; audio.rate = Float(speed); audio.volume = playbackVolume; audio.delegate = self
                        player = audio; currentSentence = sentenceIndex; state = .playing
                        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                            playback = continuation
                            if !audio.play() { playback = nil; continuation.resume(returning: false) }
                        }
                        guard ticket == session && !Task.isCancelled else { return }
                        player?.delegate = nil; player = nil
                        try? FileManager.default.removeItem(at: unit)
                        guard success else { throw AppError.message("Audio playback failed.") }
                        partIndex += 1
                    }
                    guard ticket == session else { return }
                    sentenceIndex += 1; partIndex = 0
                }
                guard ticket == session else { return }
                releaseAudio(); state = .finished; currentSentence = nil; pipeline = nil
            } catch {
                guard ticket == session else { return }
                releaseAudio(); pipeline = nil; state = .idle
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }
    func pause() {
        if state == .playing { player?.pause(); state = .paused }
        else if state == .generating { cancelPipeline(resetPosition: false); state = .paused }
    }
    func stop() { cancelPipeline(resetPosition: true); if state != .importing { state = .idle } }
    private func cancelPipeline(resetPosition: Bool) {
        session = UUID(); pipeline?.cancel(); pipeline = nil; worker?.cancel(); worker = nil
        player?.stop(); player?.delegate = nil; player = nil
        let waiting = playback; playback = nil; waiting?.resume(returning: false)
        if let work { try? FileManager.default.removeItem(at: work) }; work = nil
        if resetPosition { sentenceIndex = 0; partIndex = 0; currentSentence = nil }
    }
    private func releaseAudio() {
        worker = nil; player?.delegate = nil; player = nil; playback = nil
        if let work { try? FileManager.default.removeItem(at: work) }; work = nil
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            let waiting = self.playback; self.playback = nil; waiting?.resume(returning: flag)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
}
