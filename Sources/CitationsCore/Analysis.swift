import Foundation

// A port of qdvcrc_analysis.py (and the orchestration in check_refs.py):
// matching in-text citations against the reference list, finding unused
// references, and the six style checks. Findings are listed in the order
// the Python report prints them: sorted for in-text citations and unused
// references, in reading order for the other reference checks.

extension Patterns {
    /// "and" as a whole word (not inside "Anderson" or "Brand"), and "&".
    static let andSeparator = Pattern(#"(?<![\w&])and(?![\w])"#, caseInsensitive: true)
    static let ampersandSeparator = Pattern(#"&"#)

    /// The two volume/issue formats: "(16:2)", and "16(2)" / "16 (2)".
    static let parentheticalVolumeIssue = Pattern(#"\(\s*\d+\s*:\s*\d+\s*\)"#)
    static let commaVolumeIssue = Pattern(#"\b\d+\s*\(\s*\d+\s*\)"#)

    /// A stray comma before a parenthetical volume/issue: "Journal, (16:2)".
    static let commaBeforeParenthetical = Pattern(#",\s*\(\s*\d+\s*:\s*\d+\s*\)"#)

    /// "In" or "In:" leading to an edited collection (a book chapter).
    static let inContainer = Pattern(#"\bIn:?\s"#)

    /// The separator that is wrong when `separator` is the right one.
    static func wrongSeparator(for separator: AuthorSeparator) -> Pattern {
        separator == .and ? ampersandSeparator : andSeparator
    }
}

/// Whether the text after a reference's year looks like a journal article or
/// a book chapter (a title, then a separate journal or book) rather than a
/// whole book: it has a volume/issue (either format) or an "In:". Whole books
/// have neither. An article with neither reads as a book, which only means
/// its title isn't checked (the safe direction).
func isArticleOrChapter(_ postYear: String) -> Bool {
    Patterns.parentheticalVolumeIssue.found(in: postYear)
        || Patterns.commaVolumeIssue.found(in: postYear)
        || Patterns.inContainer.found(in: postYear)
}

/// Whether an in-text citation ("Smith, 2026", "Smith et al 2026") follows
/// the comma style. A citation with no year passes.
func matchesInTextStyle(_ citation: String, usesComma: Bool) -> Bool {
    guard let year = Patterns.year.search(citation) else { return true }
    let beforeYear = NSString(string: citation).substring(to: year.range.location).pyRStrip
    return beforeYear.pyEndsWith(",") == usesComma
}

/// The citation rewritten in the comma style: "Jones 2024" → "Jones, 2024".
func inTextStyleCorrection(_ citation: String, usesComma: Bool) -> String? {
    guard let year = Patterns.year.search(citation) else { return nil }
    let ns = NSString(string: citation)
    var before = ns.substring(to: year.range.location).pyRStrip
    if before.pyEndsWith(",") {
        before = NSString(string: before).substring(to: before.utf16Length - 1).pyRStrip
    }
    let rest = ns.substring(from: year.range.location)
    return usesComma ? "\(before), \(rest)" : "\(before) \(rest)"
}

/// A reference's sort key: its first author's surname (the text before the
/// first comma), folded to lowercase ASCII.
///
///     "Smith, J. (2026). A study of things." → "smith"
func referenceSortKey(_ line: String) -> String {
    foldToASCII(referenceLeadingAuthor(line))
}

/// The text before a reference's first comma, stripped.
func referenceLeadingAuthor(_ line: String) -> String {
    let ns = NSString(string: line)
    let comma = ns.range(of: ",")
    let head = comma.location == NSNotFound ? line : ns.substring(to: comma.location)
    return head.pyStrip
}

/// Shortens text for a one-line detail.
func excerpt(_ text: String, limit: Int = 60) -> String {
    let flat = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
    guard flat.count > limit else { return flat }
    return String(flat.prefix(limit - 1)) + "\u{2026}"
}

/// Checks manuscripts (Python: check_refs.check_citations).
public enum CitationChecker {
    /// Checks the citations in `text` against `style`. In-text citations in
    /// `whitelist` are ignored entirely.
    public static func check(_ text: String, style: CitationStyle, whitelist: Set<String> = []) -> CheckReport {
        let doc = parseDocument(text, whitelist: whitelist)
        var findings: [CheckKind: [Finding]] = [:]

        func citationFinding(_ kind: CheckKind, _ n: Int, _ record: CitationRecord, _ detail: String?) -> Finding {
            Finding(id: "\(kind.rawValue)-\(n)", kind: kind, text: record.display, checkedText: record.text, detail: detail,
                    occurrences: record.spans.map { Optional($0) })
        }
        func referenceFinding(_ kind: CheckKind, _ n: Int, _ entry: ReferenceEntry, _ detail: String?) -> Finding {
            Finding(id: "\(kind.rawValue)-\(n)", kind: kind, text: entry.text, checkedText: entry.text, detail: detail,
                    occurrences: [entry.span])
        }
        func sortedByText(_ records: [CitationRecord]) -> [CitationRecord] {
            records.sorted { $0.text.pythonLess(than: $1.text) }
        }

        let recognised = doc.citations.filter { !$0.keys.isEmpty }

        // 1 and 2: in-text citations with no reference, and references that
        // no citation matches.
        var missing: [CitationRecord] = []
        var used = Set<Int>()
        for record in recognised {
            var matched = false
            for key in record.keys {
                if let indices = doc.referencesByKey[key] {
                    matched = true
                    used.formUnion(indices)
                }
            }
            if !matched { missing.append(record) }
        }
        findings[.missingReference] = sortedByText(missing).enumerated().map { n, record in
            citationFinding(.missingReference, n, record, missingDetail(record.keys))
        }

        let unused = doc.references.indices
            .filter { !used.contains($0) }
            .map { doc.references[$0] }
            .sorted { $0.text.pythonLess(than: $1.text) }
        findings[.unusedReference] = unused.enumerated().map { n, entry in
            referenceFinding(.unusedReference, n, entry, nil)
        }

        // 3: the year comma, for citations in parentheses only (a narrative
        // citation never has a comma before its year).
        let commaViolations = recognised.filter {
            !doc.narrativeCitations.contains($0.text) && !matchesInTextStyle($0.text, usesComma: style.usesCommaInText)
        }
        findings[.inTextComma] = sortedByText(commaViolations).enumerated().map { n, record in
            let fixed = inTextStyleCorrection(record.text, usesComma: style.usesCommaInText)
            return citationFinding(.inTextComma, n, record, fixed.map { "Expected (\($0))" })
        }

        // 4: alphabetical order, each reference against the one above it.
        var order: [Finding] = []
        if doc.references.count > 1 {
            for i in 1..<doc.references.count {
                let previous = doc.references[i - 1]
                let current = doc.references[i]
                if referenceSortKey(current.text) < referenceSortKey(previous.text) {
                    let detail = "Comes after \u{201C}\(excerpt(referenceLeadingAuthor(previous.text), limit: 40))\u{201D}"
                    order.append(referenceFinding(.referenceOrder, order.count, current, detail))
                }
            }
        }
        findings[.referenceOrder] = order

        // 5 and 6: the author separator, flagged only where the wrong one is
        // actually used (one-author and comma-only entries pass).
        let wrongInText = Patterns.wrongSeparator(for: style.inTextSeparator)
        let separatorDetail: (AuthorSeparator) -> String = { right in
            "Uses \u{201C}\(right == .and ? "&" : "and")\u{201D}, not \u{201C}\(right.rawValue)\u{201D}"
        }
        findings[.inTextSeparator] = sortedByText(recognised.filter { wrongInText.found(in: $0.text) })
            .enumerated().map { n, record in
                citationFinding(.inTextSeparator, n, record, separatorDetail(style.inTextSeparator))
            }

        let wrongReference = Patterns.wrongSeparator(for: style.referenceSeparator)
        findings[.referenceSeparator] = doc.references
            .filter { wrongReference.found(in: referenceAuthorPrefix($0.text)) }
            .enumerated().map { n, entry in
                referenceFinding(.referenceSeparator, n, entry, separatorDetail(style.referenceSeparator))
            }

        // 7: the volume/issue format, looking only after the year. A
        // reference is flagged when it has the other format and not this
        // one, or (parenthetical) a comma before "(16:2)".
        let expected: Pattern
        let wrong: Pattern
        switch style.volumeIssueFormat {
        case .comma:
            expected = Patterns.commaVolumeIssue
            wrong = Patterns.parentheticalVolumeIssue
        case .parenthetical:
            expected = Patterns.parentheticalVolumeIssue
            wrong = Patterns.commaVolumeIssue
        }
        var volume: [Finding] = []
        for entry in doc.references {
            let postYear = referencePostYear(entry.text)
            var detail: String?
            if wrong.found(in: postYear) && !expected.found(in: postYear) {
                let other: VolumeIssueFormat = style.volumeIssueFormat == .comma ? .parenthetical : .comma
                detail = "Written as \(other.example), not \(style.volumeIssueFormat.example)"
            } else if style.volumeIssueFormat == .parenthetical,
                      Patterns.commaBeforeParenthetical.found(in: postYear) {
                detail = "No comma before the volume: Journal (16:2)"
            }
            if let detail {
                volume.append(referenceFinding(.volumeIssue, volume.count, entry, detail))
            }
        }
        findings[.volumeIssue] = volume

        // 8: title symbols, for articles and chapters only (whole books are
        // italicised in these styles, which plain text can't show).
        var titles: [Finding] = []
        if style.checksTitleSymbols {
            for entry in doc.references {
                guard isArticleOrChapter(referencePostYear(entry.text)) else { continue }
                let title = referenceTitle(entry.text, start: style.titleStart, end: style.titleEnd)
                guard !title.isEmpty else { continue }
                if !(title.pyStartsWith(style.titleStart) && title.pyEndsWith(style.titleEnd)) {
                    let detail = "Title read as: \(excerpt(title))"
                    titles.append(referenceFinding(.titleSymbols, titles.count, entry, detail))
                }
            }
        }
        findings[.titleSymbols] = titles

        return CheckReport(
            style: style,
            findings: findings,
            citationCount: recognised.count,
            citationOccurrenceCount: recognised.reduce(0) { $0 + $1.spans.count },
            referenceCount: doc.references.count,
            referencesHeading: doc.referencesHeading,
            appendixHeading: doc.appendixHeading
        )
    }

    /// "No reference by Smith or Jones from 2026".
    static func missingDetail(_ keys: [CitationKey]) -> String? {
        guard let year = keys.first?.year else { return nil }
        var authors: [String] = []
        for key in keys where !authors.contains(key.author) { authors.append(key.author) }
        let names: String
        switch authors.count {
        case 0: return nil
        case 1: names = authors[0]
        case 2: names = "\(authors[0]) or \(authors[1])"
        default: names = authors.dropLast().joined(separator: ", ") + " or \(authors[authors.count - 1])"
        }
        return "No reference by \(names) from \(year)"
    }
}
