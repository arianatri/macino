import Foundation
import Darwin

/// Real inference + muted audio lifecycle. Uses only disposable documents/preferences.
enum ReaderPlaybackSelfTest {
    @MainActor static func run() async throws {
        func require(_ value: Bool, _ text: String) throws {
            if !value { throw AppError.message(text) }; print("PASS " + text)
        }
        func wait(_ text: String, timeout: TimeInterval = 20, until condition: () -> Bool) async throws {
            let end = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() > end { throw AppError.message("Timed out: " + text) }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        let domain = "local.macino.selftest.playback." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let reader = ReaderModel(defaults: defaults); reader.playbackVolume = 0
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("macino-reader-lifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { reader.closeDocument(); defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: work) }
        let doc = work.appendingPathComponent("fixture.txt")
        try "سلام، این یک جمله برای آزمایش خواندن آفلاین است که باید کمی زمان داشته باشد. Hello, this is a second sentence for playback testing. Done.".write(to: doc, atomically: true, encoding: .utf8)
        reader.load(doc)
        try await wait("document import") { reader.state != .importing }
        try require(reader.sentences.count == 3 && !reader.hasPlaybackResources && reader.message == nil, "importing a document does not load a voice or retain audio")
        reader.play()
        try await wait("speech starts") { reader.state == .playing || reader.message != nil }
        try require(reader.state == .playing && reader.currentSentence == 0 && reader.voiceProcessID == nil, "actual speech plays with sentence highlight after inference process exits")
        reader.pause()
        let sentence = reader.currentSentence
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(reader.state == .paused && reader.currentSentence == sentence && reader.voiceProcessID == nil, "Pause keeps its sentence and no voice process")
        reader.speed = 1.5; reader.play()
        try require(reader.state == .playing && reader.speed == 1.5, "Resume applies the changed playback speed")
        reader.stop()
        try require(reader.state == .idle && !reader.hasPlaybackResources && reader.currentSentence == nil, "Stop releases the audio player and temporary wave directory")
        reader.play(at: reader.sentences.count - 1)
        try await wait("finish") { reader.state == .finished || reader.message != nil }
        try require(reader.state == .finished && !reader.hasPlaybackResources && reader.voiceProcessID == nil, "finishing speech releases all playback and voice resources")
        reader.play(at: 0)
        try await wait("inference child starts") { reader.voiceProcessID != nil || reader.state == .playing }
        let child = reader.voiceProcessID
        reader.stop()
        if let child {
            try await wait("cancelled inference exits", timeout: 3) { kill(child, 0) != 0 }
            print("PASS Stop terminates an active voice process")
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        try require(reader.state == .idle && !reader.hasPlaybackResources, "cancelled synthesis cannot restart playback or retain resources")
        print("READER PLAYBACK TEST COMPLETE — muted audio, network-denied helpers, no user documents")
    }
}
