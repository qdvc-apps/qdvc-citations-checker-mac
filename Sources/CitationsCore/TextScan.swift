import Foundation

// Helpers that give Swift the few Python behaviours the checker relies on:
// `re` searches (over NSRegularExpression, whose ICU engine reads the same
// pattern syntax), `str.strip()` and its notion of whitespace, line
// splitting, and Python's code-point string ordering. Positions are UTF-16
// offsets (NSRange), the units NSTextView selects in.
//
// Strings are bridged with NSString(string:) rather than `as NSString`, so
// the core also builds on Linux.

/// A span of the manuscript, in UTF-16 units.
public struct TextSpan: Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    public var end: Int { location + length }
    public var range: NSRange { NSRange(location: location, length: length) }

    /// The span moved by `offset`.
    func shifted(by offset: Int) -> TextSpan { TextSpan(location: location + offset, length: length) }
}

/// A compiled regular expression with the Python `re` calls the checker uses.
/// NSRegularExpression is immutable and safe to share between threads.
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid pattern \(pattern): \(error)")
        }
    }

    /// `re.search`: the first match anywhere in `string`.
    func search(_ string: String) -> NSTextCheckingResult? {
        let ns = NSString(string: string)
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: ns.length))
    }

    /// `re.match`: a match that starts at the beginning of `string`.
    func matchesStart(of string: String) -> Bool {
        let ns = NSString(string: string)
        return regex.firstMatch(in: string, options: [.anchored], range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// Whether `re.search` finds anything.
    func found(in string: String) -> Bool { search(string) != nil }

    /// `re.finditer`: every non-overlapping match, left to right.
    func all(in string: String) -> [NSTextCheckingResult] {
        let ns = NSString(string: string)
        return regex.matches(in: string, options: [], range: NSRange(location: 0, length: ns.length))
    }

    /// `re.findall` for a pattern without groups: the matched strings.
    func allStrings(in string: String) -> [String] {
        let ns = NSString(string: string)
        return all(in: string).map { ns.substring(with: $0.range) }
    }

    /// `re.sub(pattern, replacement, string)` with a literal replacement.
    func replacingAll(in string: String, with replacement: String = "") -> String {
        let ns = NSString(string: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: NSRange(location: 0, length: ns.length),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }
}

extension NSTextCheckingResult {
    /// A group's range, or nil when the group did not take part in the match.
    func groupRange(_ index: Int) -> NSRange? {
        guard index < numberOfRanges else { return nil }
        let r = range(at: index)
        return r.location == NSNotFound ? nil : r
    }
}

/// Python's whitespace (`str.isspace`), for one UTF-16 unit. Every
/// whitespace character is in the Basic Multilingual Plane.
func isPythonSpace(_ u: UInt16) -> Bool {
    switch u {
    case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
        return true
    default:
        return false
    }
}

extension String {
    /// Python's `str.strip()`.
    var pyStrip: String { pyTrimmed(leading: true, trailing: true) }
    /// Python's `str.lstrip()`.
    var pyLStrip: String { pyTrimmed(leading: true, trailing: false) }
    /// Python's `str.rstrip()`.
    var pyRStrip: String { pyTrimmed(leading: false, trailing: true) }

    private func pyTrimmed(leading: Bool, trailing: Bool) -> String {
        let ns = NSString(string: self)
        let span = trimmedSpan(in: ns, TextSpan(location: 0, length: ns.length), leading: leading, trailing: trailing)
        return ns.substring(with: span.range)
    }

    /// Python's `str.lower()`, close enough for the words compared here.
    var pyLower: String { lowercased() }

    /// The number of UTF-16 units (NSString length).
    var utf16Length: Int { utf16.count }

    /// Python's `<` on strings: by code point, without normalisation.
    func pythonLess(than other: String) -> Bool {
        var a = unicodeScalars.makeIterator()
        var b = other.unicodeScalars.makeIterator()
        while true {
            switch (a.next(), b.next()) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?):
                if x.value != y.value { return x.value < y.value }
            }
        }
    }
}

/// `span` within `ns` without Python whitespace at either end.
func trimmedSpan(in ns: NSString, _ span: TextSpan, leading: Bool = true, trailing: Bool = true) -> TextSpan {
    var start = span.location
    var end = span.end
    if leading {
        while start < end, isPythonSpace(ns.character(at: start)) { start += 1 }
    }
    if trailing {
        while end > start, isPythonSpace(ns.character(at: end - 1)) { end -= 1 }
    }
    return TextSpan(location: start, length: end - start)
}

/// A non-blank line of the manuscript, stripped as Python strips it.
struct SourceLine {
    let text: String
    /// Where the stripped text is in the manuscript.
    let span: TextSpan
}

/// Splits a manuscript into stripped, non-blank lines, as Python's
/// `readlines()` (with universal newlines) followed by `strip()` would. Line
/// and paragraph separators (U+2028, U+2029), which word processors put in
/// copied text, also end a line.
func sourceLines(of text: String) -> [SourceLine] {
    let ns = NSString(string: text)
    let length = ns.length
    var lines: [SourceLine] = []

    func emit(_ start: Int, _ end: Int) {
        let span = trimmedSpan(in: ns, TextSpan(location: start, length: end - start))
        guard span.length > 0 else { return }
        lines.append(SourceLine(text: ns.substring(with: span.range), span: span))
    }

    var start = 0
    var i = 0
    while i < length {
        let u = ns.character(at: i)
        if u == 0x0A || u == 0x0D || u == 0x2028 || u == 0x2029 {
            emit(start, i)
            if u == 0x0D, i + 1 < length, ns.character(at: i + 1) == 0x0A { i += 1 }
            start = i + 1
        }
        i += 1
    }
    emit(start, length)
    return lines
}

// Latin letters with no Unicode decomposition into a base letter and a
// combining mark, mapped to their conventional base form(s), so that
// alphabetical-order checking treats e.g. "ø" like "o" and "ß" like "ss".
private let foldSpecialCharacters: [Character: String] = [
    "ø": "o", "Ø": "o",
    "ł": "l", "Ł": "l",
    "ð": "d", "Ð": "d", "đ": "d", "Đ": "d",
    "ß": "ss",
    "þ": "th", "Þ": "th",
    "æ": "ae", "Æ": "ae",
    "œ": "oe", "Œ": "oe",
    "ı": "i",
    "ħ": "h", "Ħ": "h",
]

/// Reduces a string to lowercase ASCII for alphabetical comparison, folding
/// accented and other non-ASCII Latin letters to their base letters
/// ("Öqvist" → "oqvist", "Bjørnsson" → "bjornsson"). Characters with no ASCII
/// equivalent are dropped.
public func foldToASCII(_ text: String) -> String {
    var mapped = ""
    for ch in text {
        if let replacement = foldSpecialCharacters[ch] {
            mapped += replacement
        } else {
            mapped.append(ch)
        }
    }
    let decomposed = mapped.decomposedStringWithCompatibilityMapping
    var ascii = String.UnicodeScalarView()
    for scalar in decomposed.unicodeScalars where scalar.isASCII {
        ascii.append(scalar)
    }
    return String(ascii).lowercased()
}
