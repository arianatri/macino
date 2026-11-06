import Foundation

enum ReaderLanguage: String { case persian = "fa", english = "en" }
struct ReaderSpeechPart: Equatable { let text: String; let language: ReaderLanguage }
struct ReaderSentence: Identifiable { let id: Int; let text: String }

enum ReaderText {
    static let extensions: Set<String> = ["txt", "pdf", "docx", "doc"]
    static func sentences(_ text: String) -> [ReaderSentence] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "(?<!\\n)\\n(?!\\n)", with: " ", options: .regularExpression)
        var result: [ReaderSentence] = []; var buffer = ""; var ended = false
        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(ReaderSentence(id: result.count, text: trimmed)) }
            buffer = ""; ended = false
        }
        for character in normalized {
            if character == "\n" || (character.isWhitespace && (ended || buffer.count >= 420)) { flush(); continue }
            buffer.append(character)
            if ".!?؟…".contains(character) { ended = true }
            else if !"\"'”’»)]}".contains(character) { ended = false }
            if buffer.count >= 700 { flush() }
        }
        flush(); return result
    }
    static func language(of character: Character) -> ReaderLanguage? {
        guard character.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        return character.unicodeScalars.contains { (0x0600...0x08ff).contains($0.value) || (0xfb50...0xfdff).contains($0.value) || (0xfe70...0xfeff).contains($0.value) } ? .persian : .english
    }
    static func parts(_ text: String) -> [ReaderSpeechPart] {
        var language = text.compactMap { self.language(of: $0) }.first ?? .english
        var buffer = ""; var parts: [ReaderSpeechPart] = []
        func flush() {
            let clean = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { parts.append(ReaderSpeechPart(text: clean, language: language)) }
            buffer = ""
        }
        for character in text {
            if let next = self.language(of: character), next != language { flush(); language = next }
            if buffer.count >= 280 && character.isWhitespace { flush() }
            buffer.append(character)
            if buffer.count >= 350 { flush() }
        }
        flush(); return parts
    }
}

/// Give normal speed the middle of the control without allowing a zero audio rate.
enum ReaderSpeedScale {
    static func speed(at position: Double) -> Double {
        let position = min(1, max(0, position))
        return position <= 0.5 ? 0.5 + position : 1 + (position - 0.5) * 2
    }
    static func position(for speed: Double) -> Double {
        let speed = min(2, max(0.5, speed))
        return speed <= 1 ? speed - 0.5 : 0.5 + (speed - 1) / 2
    }
}
