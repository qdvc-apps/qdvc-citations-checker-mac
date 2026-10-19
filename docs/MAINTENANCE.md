# QDVC Citations Check for macOS — Maintenance Guide

The one rule that matters most: **the findings are the contract.** The core
is a port of the Python checker (qdvc-apa-citations-check), and its tests
compare findings with what the Python checker reports on
`sample-manuscript.txt`. Any change to what is found is a behaviour change:
make it in both editions, or note here why they differ.

## 1. Layout

```
Package.swift                   SwiftPM manifest (no Xcode project, no dependencies)
Sources/CitationsCore/          the checker: Foundation only, no AppKit/SwiftUI
Sources/QDVCCitationsCheck/     the SwiftUI/AppKit app
Tests/CitationsCoreTests/       unit tests
tools/make_icon.py              regenerates Resources/AppIcon.{svg,icns}
scripts/build-app.sh            builds (with the newest Xcode) and ad-hoc signs "QDVC Citations Check.app"
Resources/Info.plist            bundle id org.qdvc.citationscheck.mac
sample-manuscript.txt           trips each check once with the default style
docs/                           DESIGN, this guide
```

`CitationsCore` has no AppKit or SwiftUI imports and builds on Linux; the
app target is declared on macOS only. Strings are bridged with
`NSString(string:)` rather than `as NSString` for that reason.

### 1.0 Toolchain

Build with full Xcode. From Xcode 27, SwiftUI's `@State` is a macro whose
implementation (the SwiftUIMacros compiler plugin) ships with Xcode, so the
Command Line Tools or a swift.org toolchain fail with "plugin for module
'SwiftUIMacros' not found". `scripts/build-app.sh` therefore sets
`DEVELOPER_DIR` to the newest installed Xcode (found with Spotlight and in
`/Applications`) when `xcode-select` points at the Command Line Tools,
runs `xcrun swift` so that Xcode's compiler wins over any other on `PATH`,
prints the compiler and macOS SDK versions, and warns when the SDK is older
than 26 (no Liquid Glass). An explicit `DEVELOPER_DIR` is respected. The
same block is used in the other QDVC macOS apps; keep them in step.

AppKit decides on Liquid Glass from the SDK version recorded in the
executable's `LC_BUILD_VERSION`. `swift build` records the deployment target
there (`sdk 14.0`), so after copying the executable into the bundle the
script rewrites that field with `vtool -set-build-version macos <minos>
<sdk> -replace` to the SDK it built with, before signing. Check with
`vtool -show-build`.

### 1.1 App icon

`tools/make_icon.py` writes `Resources/AppIcon.svg` and
`Resources/AppIcon.icns` (needs `rsvg-convert`; `brew install librsvg`). The
design is a frosted-glass manuscript page (body text with citation pills,
one flagged with a red dotted underline, a References heading and three
references with match dots, joined by dotted threads) sealed with a
raspberry tick badge, in the "Blush" palette, on Apple's template geometry,
matching the other QDVC apps. `--preview` also writes
`build/icon-preview.png`.

## 2. Modules

`CitationsCore`:

| File | Responsibility | Python |
| --- | --- | --- |
| `CitationStyle.swift` | the six settings and their defaults, examples, `TitleSymbols` presets | `DEFAULT_CONFIG`, config.yml |
| `TextScan.swift` | `Pattern` (NSRegularExpression with `re`-like calls), `str.strip` whitespace, line splitting, code-point ordering, `foldToASCII`, `TextSpan` | — |
| `Parsing.swift` | the patterns; citation and reference keys; narrative and bracketed citations with their spans; sections | `qdvcrc_parsing.py` |
| `Analysis.swift` | the eight checks, details for each finding | `qdvcrc_analysis.py`, `check_refs.py` |
| `Report.swift` | `CheckKind`, `Finding`, `CheckReport` (spans kept in step with edits, a plain-text report) | `qdvcrc_report.py` |

The app (`QDVCCitationsCheck`): `CitationsCheckApp` (the window, the
delegate, the menus), `AppModel` (style, report, selection, Next/Previous
Issue, highlights, text size; `@Observable`, main actor), `ContentView`
(the split view, toolbar, placeholder), `IssueNavigator` (the sidebar),
`StyleInspector`, `ManuscriptEditor` (the text view, and `EditorBridge`,
through which the model reads the text, selects and highlights), `Prefs`.

### 2.1 Porting notes

- **Regular expressions.** The patterns are the Python ones, unchanged in
  meaning: ICU (behind NSRegularExpression) and Python's `re` treat `\w`,
  `\d`, `\s`, `\b`, lazy quantifiers and lookbehind the same way. All
  sixteen were compared, through libicu, with Python's `re` on the sample
  and edge cases (accents, hyphens, "Anderson", "COVID-19", stray commas)
  with no differences. Python's `re.match` is `Pattern.matchesStart`, and
  `fullmatch("(" + citation + ")")` is the `yearOnly` pattern.
- **Positions.** Everything is in UTF-16 units (NSRange), which is what
  NSTextView selects in. Each line is stripped as Python strips it, and its
  offset in the manuscript is kept, so a citation's span is its offset in
  the line plus the line's offset.
- **Whitespace and order.** `pyStrip` uses Python's `str.isspace` set, and
  sorting uses `pythonLess` (by code point), so findings come out in the
  Python report's order.
- **Lines.** Python's universal newlines (`\n`, `\r\n`, `\r`) end a line;
  so do U+2028 and U+2029, which word processors put in copied text.
- **Duplicates.** As in Python, a citation string is one finding however
  often it occurs; the Swift edition also keeps every occurrence's span.

### 2.2 How the text and the report stay in step

The text lives only in the `NSTextView`. The model reads it when checking
(`EditorBridge.text`). The text storage's delegate records each character
edit (`didProcessEditing`: the edited range is in the new text, so the
replaced length is its length minus the change in length) and hands them
to `AppModel.textEdited` on `textDidChange`. `CheckReport.applyEdit` moves
spans after an edit and drops spans it touched; the underlines are then
redrawn from the report.

## 3. Behaviour to preserve

- Findings match the Python checker's on the sample in both test styles
  (`AnalysisTests`).
- A finding's spans select exactly its citation or reference
  (`testFindingsPointAtTheText`).
- Book titles are never title-checked; with no symbols set, the title check
  is skipped, not passed.
- Nothing the user pastes is written anywhere.

## 4. Tests

```
swift test
```

`CoreTests.swift` covers the key readers, reference parts and titles,
narrative and bracketed citations and their spans, line splitting and
sections, the Python string helpers, both sample reports, the comma
correction, accent folding in the order check, the stray-comma case, books
and titles, spans following edits, a manuscript without a References
heading, and the style's defaults, decoding and examples.

## 5. Roadmap

Ideas raised but left out of the first version:

- Did-you-mean hints for missing citations: a near-spelling (Smtih →
  Smith) or the same author with a different year.
- Detect the style from the manuscript, and named style presets.
- An ignore list (the Python checker's `whitelist`), editable in the
  inspector.
- Copy or export the report (`CheckReport.plainText` already gives the
  Python layout).
- Open or drop a .docx, .rtf or .txt file into the text area.
