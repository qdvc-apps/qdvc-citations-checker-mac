# QDVC Citations Check for macOS

Check the APA-style citations in a paper: paste the text of your manuscript,
click **Check**, and see which in-text citations have no matching reference,
which references are never cited, and where the citation style is
inconsistent. A native SwiftUI and AppKit edition of
[qdvc-apa-citations-check](https://github.com/qdvc-apps/qdvc-apa-citations-check)
(Python), for macOS 14 (Sonoma) and later.

Nothing you paste is saved or sent anywhere: the app makes no network
calls, and the text is gone when you quit. Only the citation-style settings
are remembered.

## What it does

The window has three parts, as in Xcode: the **issues** on the left, your
**manuscript** in the middle, and the **citation style** in the inspector on
the right (⌥⌘I). Why it is laid out this way is explained in
[docs/DESIGN.md](docs/DESIGN.md).

1. **Paste** your paper into the text area. Plain text copied from your word
   processor is fine. The reference list must start with a line that begins
   with "References", and any appendix with a line that begins with
   "Appendix".
2. **Check** (⌘R). The sidebar lists what was found, check by check, with a
   count; a check with nothing to report says so. Problems are also
   underlined in the text: red where citations and references don't match
   up, orange for style.
3. **Click a finding** to select it in the text. Every occurrence of it is
   tinted, and Next Issue (⌘') steps through them, then on to the next
   finding.
4. **Fix** the text in the app or in your word processor. When the text or
   the style changes, the sidebar says the results are out of date; the
   findings still point at the right places until you check again.

The eight checks are those of the Python checker:

1. In-text citations with no reference by the same author and year
2. References that no in-text citation matches
3. In-text citations with or without a comma before the year, as set:
   (Smith, 2026) or (Smith 2026)
4. References out of alphabetical order (accented names sort by their base
   letters: Öqvist with O)
5. In-text citations using "and" or "&" before the last author, as set
6. References using "and" or "&" before the last author, as set
7. Journal volume and issue written as Journal, 16(2) or Journal (16:2), as
   set
8. Article and chapter titles wrapped in the title symbols you set (curly
   quotes by default; choose None to skip this check)

Both parenthetical (Smith 2020) and narrative Smith (2020) citations are
recognised, and citations in appendices are checked too.

What is not checked: anything other than APA-style referencing; footnotes,
unless you paste them in; DOIs and URLs; spelling (only that a citation's
spelling matches its reference's); whether references are correctly
formatted, real, or appropriate.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store); Xcode 26 or later for the
  Liquid Glass look. Full Xcode is needed, not just the Command Line Tools:
  from Xcode 27, SwiftUI's `@State` is a macro whose compiler plugin
  (SwiftUIMacros) ships only with Xcode, so a Command Line Tools or swift.org
  toolchain fails with "plugin for module 'SwiftUIMacros' not found".
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
scripts/build-app.sh            # build "build/QDVC Citations Check.app" (release)
scripts/build-app.sh --install  # …and copy it to ~/Applications
```

`scripts/build-app.sh` also records the macOS SDK it built with in the app's
binary, which is what turns on Liquid Glass (`swift build` alone writes the
deployment target there, 14.0, so a `swift run` build keeps the classic
look). Check a build with
`vtool -show-build "build/QDVC Citations Check.app/Contents/MacOS/QDVCCitationsCheck"`:
`sdk` should be 26.0 or later.

`scripts/build-app.sh` builds with Xcode's toolchain even when
`xcode-select` points at the Command Line Tools: it picks the newest Xcode
installed, and says which Xcode and macOS SDK it is using (warning if the
SDK predates Liquid Glass). To run or test from the command line, point
the tools at Xcode the same way, once per Terminal session or for good:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# or: sudo xcode-select --switch /Applications/Xcode.app
swift run                       # build and launch (debug)
swift test                      # run the unit tests
```

Or open the repository folder in Xcode (File → Open…, choose the folder that
contains `Package.swift`), pick the **QDVCCitationsCheck** scheme and press
⌘R. Xcode may ask for a team: choose **None** / **Sign to Run Locally**.

To try the app straight away, paste in `sample-manuscript.txt`: it trips
each of the eight checks once with the default style.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it — no account, no
certificate, no notarisation. If you give the app to someone else, macOS
will block the first launch; they can allow it in **System Settings →
Privacy & Security → Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Citations Check.app"
```

## App icon

The icon, a frosted-glass manuscript page with citation pills threaded to a
short reference list (one citation flagged in red), sealed with a raspberry
tick badge, is generated by `tools/make_icon.py` on Apple's macOS icon
template, in the same style as the other QDVC apps (docs/MAINTENANCE.md
§1.1). It appears in the `.app` built by `scripts/build-app.sh`, not with
`swift run`.

## Where things are stored

- The manuscript: nowhere. It lives only in the window and is discarded
  when you quit.
- The citation style, the text size, whether the inspector is shown and
  whether issues are underlined: the standard macOS defaults domain
  (`defaults read org.qdvc.citationscheck.mac`).

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘R | Check citations |
| ⌘' / ⇧⌘' | Next / previous issue (every occurrence, then the next finding) |
| ⌥⌘I | Show or hide the inspector (the citation style) |
| ⌘, | Show the inspector |
| ⌃⌘S | Show or hide the issues sidebar |
| ⌘+ / ⌘− / ⌘0 | Larger / smaller / default text |
| ⌘F | Find in the manuscript |

## Q&A

**Is this reliable?** It is a port of a quick, dirty and vibe-coded checker.
Use it as a second opinion after you've checked the old-fashioned way. Its
unit tests compare its findings with the Python checker's on the sample
manuscript, in two different styles.

**How can I be sure it runs offline?** Read the code: the core
(`Sources/CitationsCore`) uses Foundation only, and nothing in the app opens
a network connection.
