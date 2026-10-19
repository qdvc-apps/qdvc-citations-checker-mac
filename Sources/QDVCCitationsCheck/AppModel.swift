import AppKit
import CitationsCore
import Observation
import SwiftUI

/// What the issue navigator can select: a finding, or a section heading.
enum NavigatorItem: Hashable {
    case finding(Finding.ID)
    case referencesHeading
    case appendixHeading
}

/// The app's state: the citation style, the last check's report, and what
/// is selected. The manuscript itself lives only in the text view (nothing
/// is stored), which the model reaches through `editor`.
@MainActor
@Observable
final class AppModel {
    /// The style the next check uses (the inspector edits it). Saved.
    var style: CitationStyle = Prefs.style {
        didSet { if style != oldValue { Prefs.style = style } }
    }

    /// The last check's findings, with spans kept in step with later edits.
    private(set) var report: CheckReport?
    /// Whether the text has been edited since the last check.
    private(set) var textChangedSinceCheck = false
    /// Whether the manuscript is empty.
    private(set) var isTextEmpty = true

    /// The selected finding or heading in the issue navigator.
    var selection: NavigatorItem? {
        didSet { if selection != oldValue { selectionChanged() } }
    }
    /// Which occurrence of the selected finding is shown (Next Issue steps
    /// through them).
    private(set) var occurrenceIndex = 0

    var inspectorShown: Bool = Prefs.inspectorShown {
        didSet { Prefs.inspectorShown = inspectorShown }
    }
    var columnVisibility: NavigationSplitViewVisibility = .all

    /// Whether findings are underlined in the text.
    var underlineIssues: Bool = Prefs.underlineIssues {
        didSet {
            Prefs.underlineIssues = underlineIssues
            refreshHighlights()
        }
    }

    /// The manuscript's text size.
    var fontSize: Double = Prefs.fontSize {
        didSet {
            Prefs.fontSize = fontSize
            editor.setFontSize(fontSize)
        }
    }

    /// Constants are not observed, so this needs no @ObservationIgnored.
    let editor = EditorBridge()
    /// On while Next/Previous Issue sets the selection itself.
    @ObservationIgnored private var steppingSelection = false

    // MARK: - State

    /// Whether the style has changed since the last check.
    var styleChangedSinceCheck: Bool { report.map { $0.style != style } ?? false }

    /// Whether the report no longer describes the text and settings.
    var isStale: Bool { report != nil && (textChangedSinceCheck || styleChangedSinceCheck) }

    /// Why the report is out of date.
    var staleReason: String {
        switch (textChangedSinceCheck, styleChangedSinceCheck) {
        case (true, true): return "The text and the citation style have changed since this check."
        case (true, false): return "The text has changed since this check."
        default: return "The citation style has changed since this check."
        }
    }

    var hasIssues: Bool { (report?.issueCount ?? 0) > 0 }

    /// The window's subtitle.
    var statusText: String {
        guard let report else { return isTextEmpty ? "Paste your paper to begin" : "Not checked yet" }
        let n = report.issueCount
        let issues = n == 0 ? "No issues" : "\(n) issue\(n == 1 ? "" : "s")"
        return isStale ? "\(issues) \u{00B7} out of date" : issues
    }

    // MARK: - Checking

    /// Checks the manuscript against the current style.
    func check() {
        report = CitationChecker.check(editor.text, style: style)
        textChangedSinceCheck = false
        selection = nil
        occurrenceIndex = 0
        refreshHighlights()
        if columnVisibility == .detailOnly { columnVisibility = .all }
    }

    /// The text view reports edits here: the report's spans follow them.
    func textEdited(_ edits: [TextEdit], isEmpty: Bool) {
        isTextEmpty = isEmpty
        if isEmpty {
            // Nothing left to describe: back to the "not checked" state.
            report = nil
            textChangedSinceCheck = false
            selection = nil
            return
        }
        guard report != nil, !edits.isEmpty else { return }
        for edit in edits {
            report?.applyEdit(at: edit.location, replaced: edit.replaced, inserted: edit.inserted)
        }
        textChangedSinceCheck = true
        refreshHighlights()
    }

    // MARK: - Navigation

    /// The span a navigator item points at, for the current occurrence.
    private func span(of item: NavigatorItem?) -> TextSpan? {
        guard let report, let item else { return nil }
        switch item {
        case .finding(let id):
            guard let finding = report.finding(id: id), finding.occurrences.indices.contains(occurrenceIndex) else {
                return nil
            }
            return finding.occurrences[occurrenceIndex]
        case .referencesHeading:
            return report.referencesHeading
        case .appendixHeading:
            return report.appendixHeading
        }
    }

    private func selectionChanged() {
        guard !steppingSelection else { return }
        occurrenceIndex = firstLiveOccurrence(of: selection) ?? 0
        revealSelection()
    }

    private func firstLiveOccurrence(of item: NavigatorItem?) -> Int? {
        guard case .finding(let id)? = item, let finding = report?.finding(id: id) else { return nil }
        return finding.occurrences.firstIndex { $0 != nil }
    }

    /// Selects the current occurrence in the text and scrolls to it.
    func revealSelection() {
        refreshMarks()
        if let span = span(of: selection) {
            editor.reveal(span.range)
        }
    }

    /// Shows a navigator item in the text, selecting it if need be.
    func show(_ item: NavigatorItem) {
        if selection == item {
            revealSelection()
        } else {
            selection = item
        }
    }

    /// Every occurrence of every finding still in the text, in navigator
    /// order: where Next and Previous Issue go.
    private var stops: [(id: Finding.ID, index: Int)] {
        guard let report else { return [] }
        var stops: [(id: Finding.ID, index: Int)] = []
        for finding in report.allFindings {
            for (i, span) in finding.occurrences.enumerated() where span != nil {
                stops.append((id: finding.id, index: i))
            }
        }
        return stops
    }

    /// Moves to the next (1) or previous (-1) occurrence of a finding,
    /// through every occurrence of the selected finding before the next one.
    func step(_ delta: Int) {
        let stops = self.stops
        guard !stops.isEmpty else {
            NSSound.beep()
            return
        }
        var current: Int?
        if case .finding(let id)? = selection {
            current = stops.firstIndex { $0.id == id && $0.index == occurrenceIndex }
                ?? stops.firstIndex { $0.id == id }
        }
        let next: Int
        if let current {
            next = ((current + delta) % stops.count + stops.count) % stops.count
        } else {
            next = delta > 0 ? 0 : stops.count - 1
        }
        let stop = stops[next]
        steppingSelection = true
        selection = .finding(stop.id)
        steppingSelection = false
        occurrenceIndex = stop.index
        revealSelection()
    }

    // MARK: - Highlights

    /// The colour a finding is underlined in: red for citations and
    /// references that don't match up, orange for style.
    static func color(for kind: CheckKind) -> NSColor {
        kind.isMatching ? .systemRed : .systemOrange
    }

    /// Underlines every finding still in the text (when switched on).
    func refreshHighlights() {
        var underlines: [(NSRange, NSColor)] = []
        if underlineIssues, let report {
            for finding in report.allFindings {
                let color = Self.color(for: finding.kind)
                for case let span? in finding.occurrences {
                    underlines.append((span.range, color))
                }
            }
        }
        editor.setUnderlines(underlines)
        refreshMarks()
    }

    /// Tints every occurrence of the selected finding.
    private func refreshMarks() {
        var ranges: [NSRange] = []
        if case .finding(let id)? = selection, let finding = report?.finding(id: id) {
            ranges = finding.occurrences.compactMap { $0?.range }
        }
        editor.setMarks(ranges)
    }

    // MARK: - Text size

    /// Bigger (1), smaller (-1) or the default size (0).
    func zoom(_ direction: Int) {
        if direction == 0 {
            fontSize = Prefs.defaultFontSize
        } else {
            let next = fontSize + Double(direction) * (fontSize >= 18 ? 2 : 1)
            fontSize = min(max(next, Prefs.fontSizeRange.lowerBound), Prefs.fontSizeRange.upperBound)
        }
    }
}
