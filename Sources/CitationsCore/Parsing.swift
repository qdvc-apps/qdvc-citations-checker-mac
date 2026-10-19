import Foundation

// A port of qdvcrc_parsing.py: reading the manuscript into body text, a
// reference list and appendices, and pulling the in-text citations and the
// references' (author, year) keys out of it. The functions keep the Python
// names (in Swift spelling) and behaviour; what is new is that each
// citation and reference also carries where it is in the text, so the app
// can select it.

/// An author's surname and a year: what citations and references are
/// matched on.
public struct CitationKey: Hashable, Sendable {
    public let author: String
    public let year: String

    public init(author: String, year: String) {
        self.author = author
        self.year = year
    }
}

/// The checker's regular expressions, as in the Python modules. ICU (behind
/// NSRegularExpression) reads them as Python's `re` does: `\w`, `\d`, `\s`
/// and `\b` are Unicode-aware in both.
enum Patterns {
    // Section headings, e.g. "References", "## 7. References", "Appendix A".
    static let referenceStart = Pattern(#"^#*\s*(?:\d+(?:\.\d+)*\s*\.?\s*)?references"#, caseInsensitive: true)
    static let appendixStart = Pattern(#"^#*\s*(?:\d+(?:\.\d+)*\s*\.?\s*)?appendix"#, caseInsensitive: true)

    /// Everything inside [] or () in a line of body text.
    static let inlineBracket = Pattern(#"\[(.*?)\]|\((.*?)\)"#)

    /// A reference's year, allowing a month or day after it: "(2023, 23 May)"
    /// or "(2023)" → "2023".
    static let referenceYear = Pattern(#"\(((?:16|17|18|19|20)\d{2})(?:,?\s*[^)]*)?\)"#)

    /// A four-digit year, optionally with a letter ("2023a"), anywhere.
    static let year = Pattern(#"\b(16\d{2}|17\d{2}|18\d{2}|19\d{2}|20\d{2})[a-z]?\b"#)

    /// A surname: a capital (ASCII or accented) and one or more further
    /// letters, optionally hyphenated ("Pries-Heje"). Two or more letters, so
    /// an initial (the "M" in "Mähring M") is not read as a surname.
    static let authorName = Pattern(#"\b[A-ZÀ-ÖØ-Þ][^\W\d_\s\-]+(?:-[^\W\d_\s]+)*"#)

    /// A parenthesis holding only a year: the year half of a narrative
    /// citation such as "Liesenfeld and Dingemanse (2024)".
    static let narrativeYear = Pattern(#"\(((?:16|17|18|19|20)\d{2})[a-z]?\)"#)

    /// A citation that is only a year (Python: narrativeYear.fullmatch of
    /// "(" + citation + ")").
    static let yearOnly = Pattern(#"^(?:16|17|18|19|20)\d{2}[a-z]?$"#)

    private static let narrativeName = #"[A-ZÀ-ÖØ-Þ][\w.'\-]*"#
    private static let narrativeConnector = #"(?:and|&|et|al\.?)"#

    /// The run of author names just before a narrative year: capitalised
    /// names joined by spaces, commas, "and", "&", "et" or "al.", anchored to
    /// the end of the text before the parenthesis, so lowercase lead-in
    /// words ("according to") end the run.
    static let narrativeAuthors = Pattern(
        #"((?:\#(narrativeName)|\#(narrativeConnector))(?:[\s,]+(?:\#(narrativeName)|\#(narrativeConnector)))*)\s*$"#
    )

    /// Parentheses and commas, removed before reading author names.
    static let citationPunctuation = Pattern(#"[(),]"#)

    /// The full stop that ends a title.
    static let sentenceEnd = Pattern(#"\.(\s|$)"#)
}

extension String {
    /// Python's `str.startswith`: compares UTF-16 units, no normalisation.
    func pyStartsWith(_ prefix: String) -> Bool { utf16.starts(with: prefix.utf16) }

    /// Python's `str.endswith`.
    func pyEndsWith(_ suffix: String) -> Bool { utf16.reversed().starts(with: suffix.utf16.reversed()) }
}

/// The (author, year) keys of an in-text citation: every capitalised name
/// with the citation's year. Handles several authors, "et al.", "&" and
/// "and".
///
///     "Smith & Jones, 2026" → [("Smith", "2026"), ("Jones", "2026")]
func citationKeys(_ citation: String) -> [CitationKey] {
    guard let match = Patterns.year.search(citation), let yearRange = match.groupRange(1) else { return [] }
    let year = NSString(string: citation).substring(with: yearRange)

    // Remove the year, parentheses and commas to leave the names.
    var namePart = Patterns.year.replacingAll(in: citation)
    namePart = Patterns.citationPunctuation.replacingAll(in: namePart).pyStrip

    return Patterns.authorName.allStrings(in: namePart)
        .filter { !["and", "et", "al"].contains($0.pyLower) }
        .map { CitationKey(author: $0, year: year) }
}

/// The (author, year) keys of a reference: the names before its year in
/// parentheses.
///
///     "Smith, J. (2026). A study of things. Journal of Things." → [("Smith", "2026")]
func referenceKeys(_ line: String) -> [CitationKey] {
    guard let match = Patterns.referenceYear.search(line), let yearRange = match.groupRange(1) else { return [] }
    let ns = NSString(string: line)
    let year = ns.substring(with: yearRange)
    let prefix = ns.substring(to: match.range.location)
    return Patterns.authorName.allStrings(in: prefix).map { CitationKey(author: $0, year: year) }
}

/// A reference's authors: the text before its year in parentheses, or "" if
/// it has no year. Used to look at author separators without matching an
/// "and" in the title or publisher.
///
///     "Smith A & Jones B (2020) Crime and punishment. Pub, City" → "Smith A & Jones B "
func referenceAuthorPrefix(_ line: String) -> String {
    guard let match = Patterns.referenceYear.search(line) else { return "" }
    return NSString(string: line).substring(to: match.range.location)
}

/// A reference after its year in parentheses (title, journal, volume and
/// issue…), or "" if it has no year.
///
///     "Smith A (2020) A study. Journal of Things, 16(2):100-110" → " A study. Journal of Things, 16(2):100-110"
func referencePostYear(_ line: String) -> String {
    guard let match = Patterns.referenceYear.search(line) else { return "" }
    return NSString(string: line).substring(from: NSMaxRange(match.range))
}

/// A reference's title: the first part after the year, up to the journal or
/// publisher. With title symbols given, a title that starts with the start
/// symbol runs to the matching end symbol (so a full stop inside the quotes
/// doesn't cut it short); otherwise it runs to the first full stop that ends
/// a sentence. "" if the reference has no year.
///
///     ("Smith A (2026). \"A study of things\". Journal of Things", "\"", "\"") → "\"A study of things\""
func referenceTitle(_ line: String, start: String = "", end: String = "") -> String {
    let postYear = referencePostYear(line)
    guard !postYear.isEmpty else { return "" }

    var region = postYear.pyStrip
    if region.pyStartsWith(".") {
        region = NSString(string: region).substring(from: 1).pyLStrip
    }

    let ns = NSString(string: region)
    if !start.isEmpty, !end.isEmpty, region.pyStartsWith(start) {
        let startLength = start.utf16Length
        let found = ns.range(of: end, options: [.literal],
                             range: NSRange(location: startLength, length: ns.length - startLength))
        if found.location != NSNotFound {
            return ns.substring(to: NSMaxRange(found))
        }
    }

    if let sentenceEnd = Patterns.sentenceEnd.search(region) {
        return ns.substring(to: sentenceEnd.range.location).pyStrip
    }
    return region.pyStrip
}

/// An in-text citation in one line: the citation text as the checker reads
/// it, and where it is in the line.
struct LineCitation {
    let text: String
    /// In the line's UTF-16 units.
    let span: TextSpan
    /// Authors in the prose and only the year in parentheses.
    let isNarrative: Bool
}

/// Narrative citations, where the authors are in the running text and only
/// the year is in parentheses, e.g. "Liesenfeld and Dingemanse (2024)". Each
/// is returned as "<authors> <year>", which the key reader treats like a
/// bracketed citation, with its span running from the first author to the
/// closing parenthesis. A parenthesised year with no names just before it
/// ("the Treaty was signed (2019)") gives nothing.
///
///     "As shown by Liesenfeld and Dingemanse (2024), this holds." → ["Liesenfeld and Dingemanse 2024"]
func narrativeCitations(in line: String) -> [LineCitation] {
    let ns = NSString(string: line)
    var citations: [LineCitation] = []
    for match in Patterns.narrativeYear.all(in: line) {
        guard let yearRange = match.groupRange(1) else { continue }
        let year = ns.substring(with: yearRange)
        // rstrip only trims the end, so offsets into `preceding` are offsets
        // into the line.
        let preceding = ns.substring(to: match.range.location).pyRStrip
        guard let authorsMatch = Patterns.narrativeAuthors.search(preceding),
              let authorsRange = authorsMatch.groupRange(1) else { continue }
        let authors = NSString(string: preceding).substring(with: authorsRange).pyStrip
        let span = TextSpan(location: authorsRange.location, length: NSMaxRange(match.range) - authorsRange.location)
        citations.append(LineCitation(text: "\(authors) \(year)", span: span, isNarrative: true))
    }
    return citations
}

/// The in-text citations in a line of body text or an appendix, without
/// those in `whitelist`. Two forms are recognised:
///
/// - bracketed citations inside [] or (), split at ";" when a bracket holds
///   several: "(Smith, 2026; Jones 2024)";
/// - narrative citations (see `narrativeCitations(in:)`), given here as
///   `narrative`.
///
/// A parenthesis holding only a year is the year half of a narrative
/// citation, not a citation of its own.
///
///     "This is shown elsewhere (Smith, 2026; Jones 2024)." → ["Smith, 2026", "Jones 2024"]
func inlineCitations(in line: String, narrative: [LineCitation], whitelist: Set<String> = []) -> [LineCitation] {
    let ns = NSString(string: line)
    var citations: [LineCitation] = []

    for match in Patterns.inlineBracket.all(in: line) {
        // The first group with text: [...] or (...).
        var content: NSRange?
        for group in 1...2 {
            if let r = match.groupRange(group), r.length > 0 {
                content = r
                break
            }
        }
        guard let content else { continue }

        var pieceStart = content.location
        let contentEnd = NSMaxRange(content)
        var i = content.location
        while i <= contentEnd {
            if i == contentEnd || ns.character(at: i) == 0x3B /* ; */ {
                let span = trimmedSpan(in: ns, TextSpan(location: pieceStart, length: i - pieceStart))
                let clean = ns.substring(with: span.range)
                pieceStart = i + 1
                if Patterns.yearOnly.found(in: clean) {
                    // The year half of a narrative citation, handled below.
                } else if !clean.isEmpty, !whitelist.contains(clean) {
                    citations.append(LineCitation(text: clean, span: span, isNarrative: false))
                }
            }
            i += 1
        }
    }

    for citation in narrative where !whitelist.contains(citation.text) {
        citations.append(citation)
    }
    return citations
}

/// A line of the reference list.
struct ReferenceEntry {
    let text: String
    let span: TextSpan
    let keys: [CitationKey]
}

/// One distinct in-text citation string, and everywhere it occurs.
struct CitationRecord {
    let text: String
    let keys: [CitationKey]
    /// Where it occurs in the manuscript, in reading order.
    var spans: [TextSpan]
    /// How it reads where it first occurs: "(Smith, 2026)" for a bracketed
    /// citation, "Liesenfeld and Dingemanse (2024)" for a narrative one.
    let display: String
}

/// The manuscript, read into sections (Python: parse_document).
struct ParsedDocument {
    /// Every reference-list line, in order.
    var references: [ReferenceEntry] = []
    /// Indices into `references`, by key.
    var referencesByKey: [CitationKey: [Int]] = [:]
    /// Distinct in-text citations, in order of first appearance.
    var citations: [CitationRecord] = []
    /// Citation text → index into `citations`.
    var citationIndex: [String: Int] = [:]
    /// The citations that are narrative (in-prose); excluded from the comma
    /// check, which is about parenthetical citations only.
    var narrativeCitations: Set<String> = []
    /// The first "References" heading, and the first "Appendix" heading.
    var referencesHeading: TextSpan?
    var appendixHeading: TextSpan?
}

/// Walks the manuscript, keeping track of the section each line is in
/// (body text, references or appendix). Body text and appendices are both
/// scanned for in-text citations; only reference-list lines make references.
func parseDocument(_ text: String, whitelist: Set<String> = []) -> ParsedDocument {
    enum Section { case text, references, appendix }

    var doc = ParsedDocument()
    var section = Section.text

    for line in sourceLines(of: text) {
        if Patterns.referenceStart.matchesStart(of: line.text) {
            section = .references
            if doc.referencesHeading == nil { doc.referencesHeading = line.span }
            continue
        }
        if Patterns.appendixStart.matchesStart(of: line.text) {
            section = .appendix
            if doc.appendixHeading == nil { doc.appendixHeading = line.span }
            continue
        }

        switch section {
        case .references:
            let keys = referenceKeys(line.text)
            let index = doc.references.count
            doc.references.append(ReferenceEntry(text: line.text, span: line.span, keys: keys))
            for key in keys {
                doc.referencesByKey[key, default: []].append(index)
            }
        case .text, .appendix:
            let narrative = narrativeCitations(in: line.text)
            for citation in narrative { doc.narrativeCitations.insert(citation.text) }
            for citation in inlineCitations(in: line.text, narrative: narrative, whitelist: whitelist) {
                let span = citation.span.shifted(by: line.span.location)
                if let index = doc.citationIndex[citation.text] {
                    doc.citations[index].spans.append(span)
                } else {
                    let display = citation.isNarrative
                        ? NSString(string: line.text).substring(with: citation.span.range)
                        : "(\(citation.text))"
                    doc.citationIndex[citation.text] = doc.citations.count
                    doc.citations.append(CitationRecord(text: citation.text, keys: citationKeys(citation.text),
                                                        spans: [span], display: display))
                }
            }
        }
    }
    return doc
}
