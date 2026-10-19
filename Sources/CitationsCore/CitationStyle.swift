import Foundation

/// The word or symbol before the last author's name.
public enum AuthorSeparator: String, CaseIterable, Codable, Sendable, Identifiable {
    /// "Smith and Jones"
    case and = "and"
    /// "Smith & Jones"
    case ampersand = "&"

    public var id: String { rawValue }
}

/// How a reference gives a journal's volume and issue.
public enum VolumeIssueFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    /// "Journal of Things, 16(2)": the volume, then the issue in parentheses.
    case comma
    /// "Journal of Things (16:2)": volume and issue together in parentheses.
    case parenthetical

    public var id: String { rawValue }

    /// The format as it looks in a reference.
    public var example: String {
        switch self {
        case .comma: return "Journal, 16(2)"
        case .parenthetical: return "Journal (16:2)"
        }
    }
}

/// The citation style a manuscript should follow: the six settings of the
/// Python checker's config.yml, with the same defaults.
public struct CitationStyle: Equatable, Codable, Sendable {
    /// (Smith, 2026) when true, (Smith 2026) when false.
    public var usesCommaInText: Bool
    /// Before the last author of an in-text citation.
    public var inTextSeparator: AuthorSeparator
    /// Before the last author of a reference.
    public var referenceSeparator: AuthorSeparator
    /// A journal's volume and issue in a reference.
    public var volumeIssueFormat: VolumeIssueFormat
    /// What a reference's title (of an article or chapter) starts with.
    /// Empty, or an empty `titleEnd`, turns the title check off.
    public var titleStart: String
    /// What a reference's title ends with.
    public var titleEnd: String

    public init(usesCommaInText: Bool = false,
                inTextSeparator: AuthorSeparator = .and,
                referenceSeparator: AuthorSeparator = .ampersand,
                volumeIssueFormat: VolumeIssueFormat = .comma,
                titleStart: String = "\u{201C}",
                titleEnd: String = "\u{201D}") {
        self.usesCommaInText = usesCommaInText
        self.inTextSeparator = inTextSeparator
        self.referenceSeparator = referenceSeparator
        self.volumeIssueFormat = volumeIssueFormat
        self.titleStart = titleStart
        self.titleEnd = titleEnd
    }

    /// The defaults (those of the Python checker).
    public static let standard = CitationStyle()

    /// Whether reference titles are checked: only with both symbols set.
    public var checksTitleSymbols: Bool { !titleStart.isEmpty && !titleEnd.isEmpty }

    /// An in-text citation in this style, e.g. "(Smith and Jones 2026)".
    public var inTextExample: String {
        "(Smith \(inTextSeparator.rawValue) Jones\(usesCommaInText ? "," : "") 2026)"
    }

    /// A one-author in-text citation in this style, e.g. "(Smith 2026)".
    public var commaExample: String {
        usesCommaInText ? "(Smith, 2026)" : "(Smith 2026)"
    }

    /// A reference in this style.
    public var referenceExample: String {
        let volume = volumeIssueFormat == .comma ? "Journal of Things, 16(2)" : "Journal of Things (16:2)"
        return "Smith A \(referenceSeparator.rawValue) Jones B (2026). \(titleStart)A study of things\(titleEnd). \(volume)"
    }

    // Decoding tolerates missing keys (each falls back to its default), so
    // settings saved by an older version still load.
    private enum CodingKeys: String, CodingKey {
        case usesCommaInText, inTextSeparator, referenceSeparator, volumeIssueFormat, titleStart, titleEnd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CitationStyle.standard
        usesCommaInText = (try? c.decodeIfPresent(Bool.self, forKey: .usesCommaInText)) ?? d.usesCommaInText
        inTextSeparator = (try? c.decodeIfPresent(AuthorSeparator.self, forKey: .inTextSeparator)) ?? d.inTextSeparator
        referenceSeparator = (try? c.decodeIfPresent(AuthorSeparator.self, forKey: .referenceSeparator)) ?? d.referenceSeparator
        volumeIssueFormat = (try? c.decodeIfPresent(VolumeIssueFormat.self, forKey: .volumeIssueFormat)) ?? d.volumeIssueFormat
        titleStart = (try? c.decodeIfPresent(String.self, forKey: .titleStart)) ?? d.titleStart
        titleEnd = (try? c.decodeIfPresent(String.self, forKey: .titleEnd)) ?? d.titleEnd
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(usesCommaInText, forKey: .usesCommaInText)
        try c.encode(inTextSeparator, forKey: .inTextSeparator)
        try c.encode(referenceSeparator, forKey: .referenceSeparator)
        try c.encode(volumeIssueFormat, forKey: .volumeIssueFormat)
        try c.encode(titleStart, forKey: .titleStart)
        try c.encode(titleEnd, forKey: .titleEnd)
    }
}

/// A common pair of title symbols, offered in the inspector's menu.
public struct TitleSymbols: Hashable, Sendable, Identifiable {
    public let name: String
    public let start: String
    public let end: String

    public var id: String { name }

    public init(name: String, start: String, end: String) {
        self.name = name
        self.start = start
        self.end = end
    }

    /// How the pair looks around a title.
    public var sample: String { start.isEmpty && end.isEmpty ? "Title" : "\(start)Title\(end)" }

    /// No symbols: the title check is off.
    public static let noSymbols = TitleSymbols(name: "None", start: "", end: "")

    public static let common: [TitleSymbols] = [
        .noSymbols,
        TitleSymbols(name: "Curly double quotes", start: "\u{201C}", end: "\u{201D}"),
        TitleSymbols(name: "Straight double quotes", start: "\"", end: "\""),
        TitleSymbols(name: "Curly single quotes", start: "\u{2018}", end: "\u{2019}"),
        TitleSymbols(name: "Straight single quotes", start: "'", end: "'"),
        TitleSymbols(name: "Low and high quotes", start: "\u{201E}", end: "\u{201C}"),
        TitleSymbols(name: "Guillemets", start: "\u{00AB}", end: "\u{00BB}"),
        TitleSymbols(name: "Reversed guillemets", start: "\u{00BB}", end: "\u{00AB}"),
    ]

    /// The common pair a style uses, or nil for a custom pair.
    public static func matching(_ style: CitationStyle) -> TitleSymbols? {
        if style.titleStart.isEmpty || style.titleEnd.isEmpty {
            return style.titleStart.isEmpty && style.titleEnd.isEmpty ? TitleSymbols.noSymbols : nil
        }
        return common.first { $0.start == style.titleStart && $0.end == style.titleEnd }
    }
}
