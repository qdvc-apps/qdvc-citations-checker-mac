import AppKit
import SwiftUI

/// An edit to the manuscript, as the text storage reports it: `replaced`
/// UTF-16 units at `location` became `inserted` units.
struct TextEdit: Sendable {
    let location: Int
    let replaced: Int
    let inserted: Int
}

/// The model's handle on the manuscript's text view. The text lives only
/// there (nothing is stored), so the model reads it, selects in it and
/// highlights it through this.
@MainActor
final class EditorBridge {
    weak var textView: NSTextView?

    /// The manuscript.
    var text: String { textView?.string ?? "" }

    private var length: Int { textView.map { ($0.string as NSString).length } ?? 0 }

    /// Selects `range`, scrolls to it and points it out, as Find does.
    func reveal(_ range: NSRange) {
        guard let tv = textView, NSMaxRange(range) <= length else { return }
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        tv.showFindIndicator(for: range)
    }

    /// Dotted underlines, as for spelling, drawn by the layout manager (they
    /// are not part of the text, so copying and undo don't see them).
    func setUnderlines(_ items: [(NSRange, NSColor)]) {
        guard let lm = textView?.layoutManager else { return }
        let full = NSRange(location: 0, length: length)
        lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        let style = NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue
        for (range, color) in items where NSMaxRange(range) <= full.length {
            lm.addTemporaryAttributes([.underlineStyle: style, .underlineColor: color], forCharacterRange: range)
        }
    }

    /// A tint behind each occurrence of the selected finding.
    func setMarks(_ ranges: [NSRange]) {
        guard let lm = textView?.layoutManager else { return }
        let full = NSRange(location: 0, length: length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        let tint = NSColor.systemYellow.withAlphaComponent(0.32)
        for range in ranges where NSMaxRange(range) <= full.length {
            lm.addTemporaryAttribute(.backgroundColor, value: tint, forCharacterRange: range)
        }
    }

    func setFontSize(_ size: Double) {
        guard let tv = textView else { return }
        let attributes = Self.attributes(size: size)
        tv.font = attributes[.font] as? NSFont
        tv.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        tv.typingAttributes = attributes
        if let storage = tv.textStorage, storage.length > 0 {
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    /// The manuscript's look: the user's document font (as in TextEdit),
    /// with a little extra line spacing.
    static func attributes(size: Double) -> [NSAttributedString.Key: Any] {
        let font = NSFont.userFont(ofSize: CGFloat(size)) ?? NSFont.systemFont(ofSize: CGFloat(size))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        paragraph.paragraphSpacing = CGFloat(size) * 0.3
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }
}

/// The manuscript: a plain-text NSTextView in a scroll view. TextKit 1, so
/// the layout manager can draw the issue underlines.
struct ManuscriptEditor: NSViewRepresentable {
    let model: AppModel

    /// Where the text starts inside the view (for the placeholder).
    static let inset = NSSize(width: 24, height: 20)

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        // The scroll view and the text view start at the same (arbitrary)
        // size; from then on the text view follows the scroll view's width.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let contentSize = scroll.contentSize
        let container = NSTextContainer(size: NSSize(width: contentSize.width,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: container)
        tv.minSize = NSSize(width: 0, height: contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = Self.inset

        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        // The text is checked as pasted: nothing may change quotes, dashes or
        // spelling behind the writer's back, and spelling underlines would be
        // confused with the issue underlines.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false

        let attributes = EditorBridge.attributes(size: model.fontSize)
        tv.font = attributes[.font] as? NSFont
        tv.textColor = .textColor
        tv.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        tv.typingAttributes = attributes

        tv.delegate = context.coordinator
        tv.textStorage?.delegate = context.coordinator
        tv.setAccessibilityLabel("Manuscript")

        scroll.documentView = tv
        model.editor.textView = tv
        // Ready to paste into straight away.
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        if let tv = scroll.documentView as? NSTextView, model.editor.textView !== tv {
            model.editor.textView = tv
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let model: AppModel
        /// Edits since the last textDidChange.
        var pending: [TextEdit] = []

        init(model: AppModel) {
            self.model = model
        }

        /// Records each change to the characters, exactly as the text
        /// storage reports it: the edited range is in the new text, so the
        /// replaced length is the edited length minus the change in length.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            let edit = TextEdit(location: editedRange.location, replaced: editedRange.length - delta,
                                inserted: editedRange.length)
            MainActor.assumeIsolated {
                pending.append(edit)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let edits = pending
            pending = []
            model.textEdited(edits, isEmpty: tv.string.isEmpty)
        }
    }
}
