# QDVC Citations Check for macOS — Design

Status: **first implementation written.**

QDVC Citations Check is the Mac edition of the Python checker
qdvc-apa-citations-check. It follows the approach of the other QDVC macOS
apps (Progress, Response Letter, Meetings, Nice Mail, Bibliotheca, GTD EML):
a Foundation-only core library with unit tests, a SwiftUI/AppKit front-end,
no Xcode project file, and an ad-hoc-signed bundle built by
`scripts/build-app.sh`.

## 1. Principles

- **Paste, check, fix, check again.** The whole app serves that loop; there
  is nothing to open, save or set up first.
- **Nothing is kept** but the citation style. The manuscript lives only in
  the window, so there are no documents, files or recent items.
- **Checking is on demand** (⌘R), not as you type. When the text or the
  style changes, the results say they are out of date instead of changing
  under you.
- **Same findings as the Python checker.** The core is a port of its
  parsing and analysis, and the tests compare findings on the same sample.
- **Look like Xcode where it has an answer:** issues in a navigator on the
  left, the editor in the middle, an inspector on the right, ⌘' for the
  next issue.
- **Every action is in the menu bar.** Toolbar buttons and the sidebar's
  context menu are shortcuts, never the only way in.

## 2. Layout: navigator, editor, inspector

```
┌ Issues (sidebar) ─────┬ Manuscript ─────────────────────┬ Style (inspector) ┐
│ Summary               │                                 │ In-text Citations │
│  ⚠ 8 issues found     │ … time sheets (Nguyen 2025),    │  Year  (Smith 2026)│
│  12 cited works, 10…  │              ┄┄┄┄┄┄┄┄┄┄┄ red    │  Last author  and │
│  Reference List       │ … (Smith & Jones 2020).         │  (Smith and Jones │
│ 1. Cited, Not in Re… 1│      ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ orange    │   2026)           │
│  ⛔ (Nguyen 2025)     │                                 │ Reference List    │
│ 2. In References, … 1 │ References                      │  Last author  &   │
│ 3. In-text Year Com… 1│ Adams Z (2015). “An entry …     │  Volume  J, 16(2) │
│ …                     │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ red    │  Title symbols “” │
└───────────────────────┴─────────────────────────────────┴───────────────────┘
```

The brief asked for a big text area and an inspector for the settings. The
results needed a home too, and three were possible: a tab in the
inspector, a pane under the text, or a sidebar. The sidebar won:

- **Apple's roles for the two side panes fit exactly.** In the Human
  Interface Guidelines, a sidebar is for navigating the content and an
  inspector is for the properties of the content. The findings are places
  to go in the text (each click selects one); the style is a setting of the
  check. Xcode, the app whose job is closest (an editor with a list of
  issues found in it), puts its issue navigator on the left and its
  inspectors on the right.
- **You see the findings and the settings at the same time.** A common
  move is to look at a finding, decide the setting is wrong (the journal
  uses "&", not "and"), change it and check again. With the results in an
  inspector tab, every round trip would switch tabs.
- **Long references need height, not width.** A sidebar gives a list the
  full window height; a pane under the text would take height from the
  manuscript instead.
- **Either side can go.** The sidebar hides with ⌃⌘S (or the toolbar
  button), the inspector with ⌥⌘I, leaving just the text.

The inspector shows only the style: there is nothing else selectable to
inspect. Each section shows an example in the chosen style
("(Smith and Jones 2026)"), so the settings can be read without knowing
the terms.

## 3. The manuscript

- A plain-text `NSTextView` (TextKit 1) in a scroll view, in the user's
  document font (as TextEdit uses), with ⌘+ / ⌘− for size and the standard
  Find bar.
- Smart quotes, dashes, text replacement and spelling correction are off:
  the checker looks at exact characters (curly or straight quotes around a
  title), and nothing should change them behind the writer's back.
  Spelling underlines are off too, so they aren't confused with the issue
  underlines.
- Findings are underlined as temporary attributes of the layout manager,
  like spelling marks: they are not part of the text, so they don't copy,
  undo or affect the check. Red for the matching checks (1–2), orange for
  style (3–8). Check › Underline Issues in Text turns them off.
- While the text is empty, a hint says what to paste and how the reference
  list and appendices must be headed.

## 4. Findings

- One row per distinct citation or reference, as in the Python report:
  in-text citations sorted, reference checks in reading order. Narrative
  citations show as they read ("Liesenfeld and Dingemanse (2024)").
- A citation used several times has a count; selecting it tints every
  occurrence and selects the first, and Next Issue (⌘') goes through the
  rest before moving to the next finding. The row says "Occurrence 2 of 3".
- Each row has a short detail where the check's title doesn't say it all:
  "No reference by Nguyen from 2025", "Expected (Patel 2018)",
  "Comes after “Smith”", "Written as Journal (16:2), not Journal, 16(2)",
  "Title read as: …".
- A check with no findings says so with a green tick, as the Python report
  says "None!"; the title check says when it was skipped.
- The summary at the top counts cited works and references, and links to
  where the reference list (and the first appendix) starts. If there is no
  "References" heading, it says so prominently: then every line is read as
  body text, and every citation would be reported as missing.

## 5. Out-of-date results

After a check, edits don't re-run it. Instead:

- The text storage reports each edit; the report moves every finding's
  spans to match (`CheckReport.applyEdit`), so clicking a finding still
  selects the right text. A finding whose text was edited is dimmed
  ("Edited since the check").
- A banner over the sidebar says what changed (the text, the style, or
  both) with a Check Again button, and the window subtitle says "out of
  date".
- Clearing the text clears the results.

## 6. Decisions

| Question | Decision |
| --- | --- |
| Where do results go? | A sidebar navigator (§2). |
| Is the pasted text kept? | No; only the style settings. |
| When does checking run? | On demand (⌘R), with out-of-date results flagged. |
| Extras (did-you-mean hints, style detection, ignore list, report export)? | Not in the first version. |
| Name and bundle id | QDVC Citations Check, `org.qdvc.citationscheck.mac`. |
| Icon palette | "Blush" (pale rose to raspberry), unused by the other QDVC apps. |
