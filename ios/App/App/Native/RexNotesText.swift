import SwiftUI

/// Oct 1 — "I feel like Rex could separate it out a bit into bubbles and
/// headings. It also didn't maintain the formatting from notes with the
/// bullet points."
///
/// A list's notes were drawn as one `Text` holding the entire paste. Everything
/// the author had done to organise it — LITERATURE, BABY CLOTHES, Sleepsuits,
/// and a hundred lines beginning with a dash — arrived as an unbroken wall,
/// which is exactly what makes a genuinely useful list daunting to read.
///
/// So: read the structure that is already in the text rather than asking
/// anyone to re-enter it. Someone who typed a heading in capitals and a list
/// of dashes has already said what they meant; this just stops throwing it
/// away on the way to the screen.
///
/// Deliberately not an AI pass. The text is the author's own words and the
/// rules below are reversible and inspectable — a model rewriting somebody's
/// baby-essentials list into its own idea of sections is a much bigger promise
/// and a much worse failure when it gets it wrong. Suggesting structure is a
/// good follow-up; mangling it silently is not.
enum RexNoteBlock: Identifiable {
    case heading(String)
    case bullet(String, depth: Int)
    case paragraph(String)
    case spacer

    var id: String {
        switch self {
        case .heading(let t):      return "h:\(t)"
        case .bullet(let t, let d): return "b\(d):\(t)"
        case .paragraph(let t):    return "p:\(t)"
        case .spacer:              return "s:\(UUID().uuidString)"
        }
    }
}

enum RexNotesParser {
    /// Bullet markers people actually type, including the ones Notes and Word
    /// substitute in on their way to the clipboard.
    private static let bulletMarkers = ["- ", "– ", "— ", "• ", "* ", "· "]

    static func parse(_ text: String) -> [RexNoteBlock] {
        var blocks: [RexNoteBlock] = []
        var paragraph: [String] = []
        let lines = text.components(separatedBy: .newlines)

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // The next line with anything on it, for the "label introducing a
            // list" rule below.
            let next = lines.dropFirst(index + 1).first {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }

            if line.isEmpty {
                flushParagraph()
                if case .spacer = blocks.last {} else if !blocks.isEmpty { blocks.append(.spacer) }
                continue
            }

            if let (body, depth) = bullet(rawLine) {
                flushParagraph()
                blocks.append(.bullet(body, depth: depth))
                continue
            }

            if isHeading(line, next: next) {
                flushParagraph()
                blocks.append(.heading(heading(from: line)))
                continue
            }

            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    /// Returns the text after the marker, and how deeply it was indented —
    /// two spaces or a tab per level, which is what both Notes and Word emit.
    private static func bullet(_ rawLine: String) -> (String, Int)? {
        let indent = rawLine.prefix { $0 == " " || $0 == "\t" }
        let indentWidth = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let line = rawLine.trimmingCharacters(in: .whitespaces)

        for marker in bulletMarkers where line.hasPrefix(marker) {
            let body = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return body.isEmpty ? nil : (body, min(indentWidth / 2, 2))
        }

        // "1. ", "2) " — numbered lists, kept as bullets rather than
        // renumbered, because the author's numbers may mean something.
        if let first = line.first, first.isNumber {
            let digits = line.prefix { $0.isNumber }
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                let body = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : ("\(digits). \(body)", min(indentWidth / 2, 2))
            }
        }
        return nil
    }

    /// A heading is a short line that either shouts or announces. Two rules,
    /// both conservative — a false negative is a normal paragraph, which is
    /// what it was before; a false positive puts a sentence in bold, which is
    /// worse, so both rules require the line to be short.
    private static func isHeading(_ line: String, next: String?) -> Bool {
        guard line.count <= 60 else { return false }
        let letters = line.filter(\.isLetter)
        guard letters.count >= 2 else { return false }

        // LITERATURE, BABY CLOTHES — shouted.
        if letters.allSatisfy({ $0.isUppercase }) { return true }

        // "General:", "Sleepsuits:" — announced. A colon mid-sentence doesn't
        // count, so the whole line has to end on it.
        if line.hasSuffix(":"), !line.dropLast().contains(":") { return true }

        // "Sleepsuits" — a short unpunctuated label with a list underneath it.
        // The next-line test is what makes this safe: without it the rule
        // would bold any short sentence, and a wrongly bolded sentence is a
        // worse outcome than a heading left as a paragraph.
        if line.count <= 40,
           let last = line.last, !".!?,;:".contains(last),
           let next, bullet(next) != nil {
            return true
        }

        return false
    }

    private static func heading(from line: String) -> String {
        let trimmed = line.hasSuffix(":") ? String(line.dropLast()) : line
        // Shouted headings are easier to read as words than as capitals, and
        // the emphasis is carried by the styling now rather than the caps.
        let letters = trimmed.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) {
            return trimmed.capitalized
        }
        return trimmed
    }
}

/// Renders parsed notes. Links are detected in every block, so a bare URL
/// anywhere in the text is tappable — which is also the honest half of
/// "it didn't copy over hyperlinks": a link whose text was a word in Notes
/// arrives as plain text with no address attached, and nothing downstream can
/// invent the address back. A URL that came through as a URL now works.
struct RexNotesText: View {
    let text: String
    var font: Font = RexFont.text(15)

    private var blocks: [RexNoteBlock] { RexNotesParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                switch block {
                case .heading(let heading):
                    Text(heading)
                        .font(RexFont.display(16, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, RexSpacing.md)
                        .padding(.bottom, RexSpacing.xs)

                case .bullet(let body, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: RexSpacing.sm) {
                        Circle()
                            .fill(RexColor.mutedForeground.opacity(0.55))
                            .frame(width: depth == 0 ? 5 : 4, height: depth == 0 ? 5 : 4)
                            .offset(y: -2)
                        Text(linkified(body))
                            .font(font)
                            .foregroundStyle(RexColor.foreground.opacity(0.9))
                            .tint(RexColor.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                    .padding(.bottom, 5)

                case .paragraph(let body):
                    Text(linkified(body))
                        .font(font)
                        .foregroundStyle(RexColor.foreground.opacity(0.9))
                        .tint(RexColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, RexSpacing.xs)

                case .spacer:
                    Color.clear.frame(height: RexSpacing.xs)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func linkified(_ body: String) -> AttributedString {
        var attributed = AttributedString(body)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let ns = body as NSString
        for match in detector.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url,
                  let range = Range(match.range, in: body),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].link = url
            attributed[lower..<upper].underlineStyle = .single
        }
        return attributed
    }
}
