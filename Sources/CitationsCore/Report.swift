import Foundation

/// The eight checks, numbered as in the Python checker's report.
public enum CheckKind: Int, CaseIterable, Sendable, Identifiable, Comparable {
    case missingReference = 1
    case unusedReference
    case inTextComma
    case referenceOrder
    case inTextSeparator
    case referenceSeparator
    case volumeIssue
    case titleSymbols

    public var id: Int { rawValue }

    public static func < (a: CheckKind, b: CheckKind) -> Bool { a.rawValue < b.rawValue }

    /// Whether the check is about citations and references matching up (as
    /// opposed to consistent style).
    public var isMatching: Bool { self == .missingReference || self == .unusedReference }

    /// Whether the findings are in-text citations (else reference-list lines).
    public var isInText: Bool { self == .missingReference || self == .inTextComma || self == .inTextSeparator }

    public var title: String {
        switch self {
        case .missingReference: return "Cited, Not in References"
        case .unusedReference: return "In References, Not Cited"
        case .inTextComma: return "In-text Year Comma"
        case .referenceOrder: return "Alphabetical Order"
        case .inTextSeparator: return "In-text Author Separator"
        case .referenceSeparator: return "Reference Author Separator"
        case .volumeIssue: return "Volume and Issue"
        case .titleSymbols: return "Title Symbols"
        }
    }

    /// What a finding of this kind means, in the given style.
    public func explanation(for style: CitationStyle) -> String {
        switch self {
        case .missingReference:
            return "In-text citations with no reference by the same author and year."
        case .unusedReference:
            return "References that no in-text citation matches."
        case .inTextComma:
            return "Citations in parentheses not written as \(style.commaExample)."
        case .referenceOrder:
            return "References that should come before the one above them."
        case .inTextSeparator:
            return "In-text citations using \u{201C}\(Self.other(style.inTextSeparator))\u{201D} "
                + "instead of \u{201C}\(style.inTextSeparator.rawValue)\u{201D} before the last author."
        case .referenceSeparator:
            return "References using \u{201C}\(Self.other(style.referenceSeparator))\u{201D} "
                + "instead of \u{201C}\(style.referenceSeparator.rawValue)\u{201D} before the last author."
        case .volumeIssue:
            return "Journal articles not written as \(style.volumeIssueFormat.example)."
        case .titleSymbols:
            return style.checksTitleSymbols
                ? "Article and chapter titles not wrapped in \(style.titleStart) \(style.titleEnd). Book titles are not checked."
                : "Off: no title symbols are set in the inspector."
        }
    }

    /// What it means when there are no findings of this kind.
    public var passMessage: String {
        switch self {
        case .missingReference: return "Every in-text citation matches a reference."
        case .unusedReference: return "Every reference is cited."
        case .inTextComma: return "Every citation uses the year comma style."
        case .referenceOrder: return "The references are in alphabetical order."
        case .inTextSeparator: return "Every in-text citation uses the author separator."
        case .referenceSeparator: return "Every reference uses the author separator."
        case .volumeIssue: return "Every reference uses the volume and issue format."
        case .titleSymbols: return "Every article and chapter title uses the title symbols."
        }
    }

    private static func other(_ separator: AuthorSeparator) -> String {
        separator == .and ? "&" : "and"
    }
}

/// One problem: an in-text citation or a reference, and where it occurs.
public struct Finding: Identifiable, Hashable, Sendable {
    /// Unique within a report.
    public let id: String
    public let kind: CheckKind
    /// The citation or reference, as it reads in the manuscript.
    public let text: String
    /// The citation as the checker reads it (the Python report's text,
    /// without its parentheses), or the reference line.
    public let checkedText: String
    /// What is wrong, when the check's title doesn't say it all.
    public let detail: String?
    /// Where it occurs, in reading order. An occurrence becomes nil when the
    /// text there has been edited since the check.
    public internal(set) var occurrences: [TextSpan?]

    public init(id: String, kind: CheckKind, text: String, checkedText: String, detail: String?,
                occurrences: [TextSpan?]) {
        self.id = id
        self.kind = kind
        self.text = text
        self.checkedText = checkedText
        self.detail = detail
        self.occurrences = occurrences
    }

    /// Whether every occurrence has been edited away.
    public var isGone: Bool { occurrences.allSatisfy { $0 == nil } }
}

/// The result of checking a manuscript.
public struct CheckReport: Sendable {
    /// The style the manuscript was checked against.
    public let style: CitationStyle
    /// The findings of each check (every check has an entry, perhaps empty).
    public private(set) var findings: [CheckKind: [Finding]]
    /// Distinct in-text citations recognised (with an author and a year).
    public let citationCount: Int
    /// In-text citations recognised, counting each occurrence.
    public let citationOccurrenceCount: Int
    /// Lines in the reference list.
    public let referenceCount: Int
    /// The heading that starts the reference list, if any.
    public private(set) var referencesHeading: TextSpan?
    /// The first appendix heading, if any.
    public private(set) var appendixHeading: TextSpan?

    public init(style: CitationStyle, findings: [CheckKind: [Finding]], citationCount: Int,
                citationOccurrenceCount: Int, referenceCount: Int,
                referencesHeading: TextSpan?, appendixHeading: TextSpan?) {
        self.style = style
        var all = findings
        for kind in CheckKind.allCases where all[kind] == nil { all[kind] = [] }
        self.findings = all
        self.citationCount = citationCount
        self.citationOccurrenceCount = citationOccurrenceCount
        self.referenceCount = referenceCount
        self.referencesHeading = referencesHeading
        self.appendixHeading = appendixHeading
    }

    public func findings(_ kind: CheckKind) -> [Finding] { findings[kind] ?? [] }

    /// Every finding, check by check.
    public var allFindings: [Finding] { CheckKind.allCases.flatMap { findings($0) } }

    /// The number of findings in all checks.
    public var issueCount: Int { findings.values.reduce(0) { $0 + $1.count } }

    /// Whether a check was not run (the title check, with no symbols set).
    public func isSkipped(_ kind: CheckKind) -> Bool { kind == .titleSymbols && !style.checksTitleSymbols }

    public func finding(id: Finding.ID) -> Finding? { allFindings.first { $0.id == id } }

    /// Keeps the spans in step with an edit to the manuscript: `replaced`
    /// UTF-16 units at `location` were replaced by `inserted` units. Spans
    /// after the edit move; spans the edit touched become nil.
    public mutating func applyEdit(at location: Int, replaced: Int, inserted: Int) {
        let delta = inserted - replaced
        let editEnd = location + replaced

        func adjust(_ span: TextSpan?) -> TextSpan? {
            guard let span else { return nil }
            if span.end <= location { return span }
            if span.location >= editEnd { return span.shifted(by: delta) }
            return nil
        }

        for (kind, list) in findings {
            findings[kind] = list.map { finding in
                var f = finding
                f.occurrences = f.occurrences.map(adjust)
                return f
            }
        }
        referencesHeading = adjust(referencesHeading)
        appendixHeading = adjust(appendixHeading)
    }

    /// The report as plain text, in the layout of the Python checker's
    /// output (for tests and diagnostics).
    public var plainText: String {
        var lines = ["--- APA CITATION AUDIT REPORT ---"]
        for kind in CheckKind.allCases {
            lines.append("")
            lines.append("\(kind.rawValue). \(kind.title):")
            if isSkipped(kind) {
                lines.append("  Skipped (no title symbols configured).")
            } else if findings(kind).isEmpty {
                lines.append("  None! \(kind.passMessage)")
            } else {
                for finding in findings(kind) {
                    lines.append(kind.isInText ? "  - (\(finding.checkedText))" : "  - \(finding.checkedText)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
