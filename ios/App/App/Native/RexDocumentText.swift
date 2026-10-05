import Compression
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Oct 3 — "want to be able to upload eg. a word doc".
///
/// The import screen said "from Notes, a Word doc, an itinerary, wherever" and
/// then only offered a paste box, which works for Notes (where you can select
/// all and copy) and not for a Word document sitting in Files. This reads the
/// document itself.
///
/// Everything here happens on the phone. A list of where someone is going on
/// holiday is exactly the sort of document that shouldn't be shipped to a
/// server to be unzipped, and the text still goes through the extractor
/// afterwards — with the same disclosure as a paste — so nothing new is sent
/// anywhere, it's just no longer necessary to retype it first.
enum RexDocumentError: LocalizedError {
    /// A format that genuinely can't be read, with the way out.
    case legacyWord
    case pagesBundle
    /// Readable file, nothing in it — usually a scanned PDF.
    case noText(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .legacyWord:
            return "Rex can\u{2019}t read old .doc files. Open it in Word or Pages and save it again as .docx or PDF."
        case .pagesBundle:
            return "Couldn\u{2019}t read that Pages file \u{2014} some are saved without a readable copy inside. In Pages, use File \u{203A} Export To \u{203A} Word or PDF, then choose that."
        case .noText(let name):
            return "\(name) opened, but there was no text in it. If it\u{2019}s a scan or a photo of a page, the words are a picture rather than text \u{2014} importing it as a photo will work better."
        case .unreadable(let name):
            return "Couldn\u{2019}t read \(name). If it\u{2019}s stored in iCloud, open it once in Files so it\u{2019}s downloaded, then try again."
        }
    }
}

enum RexDocumentText {
    /// What the picker will let you choose. `.doc` is deliberately included
    /// even though it can't be parsed: a greyed-out file tells you nothing,
    /// whereas picking it gets you the sentence that explains what to do.
    static var readableTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .rtf, .pdf, .html]
        for identifier in [
            "org.openxmlformats.wordprocessingml.document",  // .docx
            "com.microsoft.word.doc",                        // .doc
            "com.apple.iwork.pages.sffpages",                // .pages
            "com.apple.iwork.pages.pages",
            "net.daringfireball.markdown",
            "org.oasis-open.opendocument.text",              // .odt, same zip shape
        ] {
            if let type = UTType(identifier) { types.append(type) }
        }
        return types
    }

    /// Matches the 200,000-character cap in extract-recommendations, so a long
    /// document is trimmed here where it can be said out loud rather than
    /// silently halfway through the server.
    static let characterLimit = 200_000

    static func extract(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw RexDocumentError.unreadable(name)
        }

        let text = try read(data, extension: url.pathExtension.lowercased(), name: name)
        let tidied = tidy(text)
        guard !tidied.isEmpty else { throw RexDocumentError.noText(name) }
        return String(tidied.prefix(characterLimit))
    }

    private static func read(_ data: Data, extension ext: String, name: String) throws -> String {
        switch ext {
        case "docx", "odt": return try wordProcessingML(data, name: name)
        case "doc":         throw RexDocumentError.legacyWord
        case "pdf":         return try pdf(data, name: name)
        case "rtf", "rtfd": return try attributed(data, type: .rtf, name: name)
        case "html", "htm": return try attributed(data, type: .html, name: name)
        case "pages":       return try pages(data, name: name)
        case "txt", "text", "md", "markdown", "csv", "tsv", "":
            return try plain(data, name: name)
        default:
            // Unknown extension — go by what the bytes actually are, because
            // an extension is a hint and a wrong guess here is a dead end for
            // a file that would have read perfectly.
            if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return try pdf(data, name: name) }
            if data.starts(with: [0x50, 0x4B]) {
                if let text = try? wordProcessingML(data, name: name) { return text }
                return try pages(data, name: name)
            }
            return try plain(data, name: name)
        }
    }

    // MARK: - Formats

    private static func plain(_ data: Data, name: String) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw RexDocumentError.unreadable(name)
    }

    private static func pdf(_ data: Data, name: String) throws -> String {
        guard let document = PDFDocument(data: data) else {
            throw RexDocumentError.unreadable(name)
        }
        if let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        // A PDF with no text layer is a scan. Say so rather than "unreadable".
        throw RexDocumentError.noText(name)
    }

    private static func attributed(
        _ data: Data,
        type: NSAttributedString.DocumentType,
        name: String
    ) throws -> String {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: type],
            documentAttributes: nil
        ) else {
            throw RexDocumentError.unreadable(name)
        }
        return attributed.string
    }

    /// A Pages file is a zip that usually carries a PDF preview for Quick Look.
    /// When it's there this works; when the document was saved without one
    /// there is nothing readable inside, hence the explicit error.
    private static func pages(_ data: Data, name: String) throws -> String {
        for entry in ["QuickLook/Preview.pdf", "preview.pdf", "Preview.pdf"] {
            if let pdfData = MiniZip.file(named: entry, in: data),
               let text = try? pdf(pdfData, name: name) {
                return text
            }
        }
        throw RexDocumentError.pagesBundle
    }

    // MARK: - .docx

    /// A .docx is a zip holding `word/document.xml`. Read the paragraphs out of
    /// it, keeping the two things that matter for a list: which paragraphs were
    /// bullets, and where a link actually pointed.
    private static func wordProcessingML(_ data: Data, name: String) throws -> String {
        guard let documentXML = MiniZip.file(named: "word/document.xml", in: data)
                ?? MiniZip.file(named: "content.xml", in: data) else {
            throw RexDocumentError.unreadable(name)
        }

        let links = MiniZip.file(named: "word/_rels/document.xml.rels", in: data)
            .map(hyperlinkTargets) ?? [:]

        let reader = WordMLReader(links: links)
        let parser = XMLParser(data: documentXML)
        parser.delegate = reader
        guard parser.parse() else { throw RexDocumentError.unreadable(name) }
        return reader.text
    }

    /// `word/_rels/document.xml.rels` maps rIdN to the address a hyperlink
    /// points at. Without this a link in a Word doc arrives as the words that
    /// were underlined and the address is lost — which is the part of
    /// "it didn't copy over hyperlinks" that is actually recoverable.
    private static func hyperlinkTargets(_ data: Data) -> [String: String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [:] }
        var targets: [String: String] = [:]
        for tag in xml.components(separatedBy: "<Relationship").dropFirst() {
            guard let id = attribute("Id", in: tag),
                  let target = attribute("Target", in: tag),
                  attribute("Type", in: tag)?.hasSuffix("/hyperlink") == true else { continue }
            targets[id] = target
        }
        return targets
    }

    /// Leading space in the needle keeps ` Target="` from matching
    /// ` TargetMode="`, which sits right next to it on external links.
    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let opening = tag.range(of: " \(name)=\"") else { return nil }
        let rest = tag[opening.upperBound...]
        guard let closing = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<closing])
        return value.isEmpty ? nil : value
    }

    // MARK: - Tidying

    /// Word writes a lot of empty paragraphs. Collapse runs of them to one
    /// blank line so the result reads like the document looked, and so
    /// RexNotesParser's "heading above a list" rule still sees what it needs.
    private static func tidy(_ text: String) -> String {
        var lines: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Walks `word/document.xml`. Paragraph in, line out.
private final class WordMLReader: NSObject, XMLParserDelegate {
    private let links: [String: String]
    private var lines: [String] = []
    private var paragraph = ""
    private var insideTextRun = false
    private var isListItem = false
    private var pendingLink: String?

    /// Oct 5 — the golf tour agenda, which is mostly tables: an overview table,
    /// a driving-distances table, and a hotel table per night with columns for
    /// name, stars, price and why to stay there.
    ///
    /// Every cell in Word is its own paragraph, so flattening paragraph-by-
    /// paragraph turned one hotel into four unrelated lines — "Vaughan Lodge",
    /// "★★★★", "€180–€320", then the description — with nothing to say they
    /// belonged together. That is what "if you have an itinerary and then hotel
    /// options in the appendix, it does not extract correctly" looks like from
    /// the extractor's side: it can see the hotels and the prices, but not
    /// which price is whose. A row collected and joined keeps them together.
    private var rowCells: [String]?
    private var cellLines: [String] = []

    init(links: [String: String]) {
        self.links = links
    }

    var text: String { lines.joined(separator: "\n") }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "w:p", "text:p":
            paragraph = ""
            isListItem = false
        case "w:numPr", "text:list-item":
            isListItem = true
        case "w:t", "text:p", "text:span":
            insideTextRun = true
        case "w:tab", "text:tab":
            paragraph += " "
        case "w:br", "w:cr", "text:line-break":
            paragraph += " "
        case "w:hyperlink", "text:a":
            if let id = attributes["r:id"] { pendingLink = links[id] }
            if let href = attributes["xlink:href"] { pendingLink = href }
        case "w:tr", "table:table-row":
            rowCells = []
            cellLines = []
        case "w:tc", "table:table-cell":
            cellLines = []
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTextRun { paragraph += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "w:t", "text:span":
            insideTextRun = false
        case "w:hyperlink", "text:a":
            // Only worth adding when the address isn't already the link text —
            // plenty of documents just paste the URL in as the words.
            if let target = pendingLink,
               target.hasPrefix("http"),
               !paragraph.contains(target) {
                paragraph += " (\(target))"
            }
            pendingLink = nil
        case "w:p", "text:p":
            insideTextRun = false
            emitParagraph()
        case "w:tc", "table:table-cell":
            // A cell can hold several paragraphs; they're one value.
            let cell = cellLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            cellLines = []
            if rowCells != nil { rowCells?.append(cell) }
        case "w:tr", "table:table-row":
            let cells = (rowCells ?? []).filter { !$0.isEmpty }
            rowCells = nil
            cellLines = []
            // A one-cell row is just a line; only a real row needs separators.
            if cells.count == 1 {
                lines.append(cells[0])
            } else if !cells.isEmpty {
                lines.append(cells.joined(separator: " | "))
            }
        default:
            break
        }
    }

    private func emitParagraph() {
        let line = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        paragraph = ""
        guard !line.isEmpty else {
            // A blank paragraph inside a cell is spacing, not a paragraph break.
            if rowCells == nil { lines.append("") }
            return
        }
        // Word carries "this was a bullet" as list numbering rather than as a
        // character, so re-add the dash the author saw on screen — both the
        // extractor and RexNotesParser read dashes.
        let alreadyMarked = ["-", "\u{2013}", "\u{2014}", "\u{2022}", "*", "\u{00B7}"]
            .contains { line.hasPrefix($0) }
        let decorated = isListItem && !alreadyMarked ? "- \(line)" : line
        if rowCells == nil {
            lines.append(decorated)
        } else {
            cellLines.append(decorated)
        }
    }
}

/// Just enough ZIP to pull one named file out of a .docx or .pages, read from
/// the central directory rather than by scanning local headers — local headers
/// are allowed to carry zeroes for the sizes, the central directory never is.
private enum MiniZip {
    static func file(named name: String, in data: Data) -> Data? {
        guard let eocd = endOfCentralDirectory(data) else { return nil }
        let entries = Int(u16(data, eocd + 10))
        var offset = Int(u32(data, eocd + 16))

        for _ in 0..<entries {
            guard offset + 46 <= data.count, u32(data, offset) == 0x0201_4b50 else { return nil }
            let method = Int(u16(data, offset + 10))
            let compressedSize = Int(u32(data, offset + 20))
            let uncompressedSize = Int(u32(data, offset + 24))
            let nameLength = Int(u16(data, offset + 28))
            let extraLength = Int(u16(data, offset + 30))
            let commentLength = Int(u16(data, offset + 32))
            let localOffset = Int(u32(data, offset + 42))

            if string(data, at: offset + 46, count: nameLength) == name {
                return payload(
                    data,
                    localOffset: localOffset,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return nil
    }

    private static func payload(
        _ data: Data,
        localOffset: Int,
        method: Int,
        compressedSize: Int,
        uncompressedSize: Int
    ) -> Data? {
        guard localOffset + 30 <= data.count, u32(data, localOffset) == 0x0403_4b50 else { return nil }
        let nameLength = Int(u16(data, localOffset + 26))
        let extraLength = Int(u16(data, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        guard compressedSize >= 0, start >= 0, start + compressedSize <= data.count else { return nil }

        let base = data.startIndex
        let body = data.subdata(in: (base + start)..<(base + start + compressedSize))
        switch method {
        case 0:  return body                                        // stored
        case 8:  return inflate(body, expected: uncompressedSize)   // deflate
        default: return nil                                         // zip64/lzma: not ours
        }
    }

    /// Compression's COMPRESSION_ZLIB is raw DEFLATE per RFC 1951, which is
    /// exactly what a zip entry holds — no header to strip.
    private static func inflate(_ data: Data, expected: Int) -> Data? {
        guard expected > 0, expected < 64 << 20 else { return expected == 0 ? Data() : nil }
        var output = Data(count: expected)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            data.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, expected,
                    sourceBase, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    /// The end-of-central-directory record is last, after a comment of up to
    /// 64K, so it has to be found by scanning backwards.
    private static func endOfCentralDirectory(_ data: Data) -> Int? {
        let minimum = 22
        guard data.count >= minimum else { return nil }
        let earliest = max(0, data.count - minimum - 65_535)
        var offset = data.count - minimum
        while offset >= earliest {
            if u32(data, offset) == 0x0605_4b50 { return offset }
            offset -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ index: Int) -> UInt16 {
        let base = data.startIndex + index
        guard index >= 0, base + 2 <= data.endIndex else { return 0 }
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    private static func u32(_ data: Data, _ index: Int) -> UInt32 {
        let base = data.startIndex + index
        guard index >= 0, base + 4 <= data.endIndex else { return 0 }
        return UInt32(data[base])
            | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16
            | UInt32(data[base + 3]) << 24
    }

    private static func string(_ data: Data, at index: Int, count: Int) -> String? {
        let base = data.startIndex + index
        guard count >= 0, base + count <= data.endIndex else { return nil }
        return String(data: data.subdata(in: base..<(base + count)), encoding: .utf8)
    }
}
