import Foundation
import AppKit
import PDFKit

let maxCharacters = 2_000_000
func fail(_ message: String) -> NSError { NSError(domain: "macino.Reader", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
func extract(_ url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else { throw fail("Drop a document file, not a folder.") }
    guard (values.fileSize ?? 0) <= 100 * 1024 * 1024 else { throw fail("This document is larger than 100 MB. Split it into smaller files.") }
    let text: String
    switch url.pathExtension.lowercased() {
    case "txt":
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            guard let decoded = String(data: data, encoding: .utf16) else { throw fail("Save this text file as UTF-8 or UTF-16.") }
            text = decoded
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else { throw fail("Save this text file as UTF-8 or UTF-16.") }
            text = decoded
        }
    case "pdf":
        guard let document = PDFDocument(url: url) else { throw fail("This PDF could not be opened.") }
        guard !document.isLocked else { throw fail("This PDF is password protected. Save an unlocked copy first.") }
        var pages: [String] = []; var length = 0
        for index in 0..<document.pageCount {
            let page = autoreleasepool { document.page(at: index)?.string ?? "" }
            length += page.count
            guard length <= maxCharacters else { throw fail("This document contains too much text. Split it into smaller documents.") }
            pages.append(page)
        }
        text = pages.joined(separator: "\n\n")
    case "docx", "doc":
        let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "docx" ? .officeOpenXML : .docFormat
        text = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
    default: throw fail("Supported documents: TXT, PDF with selectable text, DOCX and DOC.")
    }
    guard text.count <= maxCharacters else { throw fail("This document contains too much text. Split it into smaller documents.") }
    let clean = text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\u{0000}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { throw fail(url.pathExtension.lowercased() == "pdf" ? "No selectable text was found. Scanned PDFs are not supported; OCR is not included." : "This document contains no readable text.") }
    return clean
}
do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let request = try JSONSerialization.jsonObject(with: input) as? [String: String], let path = request["path"] else { throw fail("Invalid document request.") }
    let text = try extract(URL(fileURLWithPath: path))
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: ["text": text]))
} catch {
    if let data = try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]) { FileHandle.standardOutput.write(data) }
    exit(1)
}
