import XCTest
@testable import CitationsCore

/// The sample manuscript (sample-manuscript.txt at the repository root).
let sampleManuscript = """
Measuring the Unmeasurable: A Sample Manuscript

Abstract

This sample paper exists to show what QDVC Citations Check finds. Paste it into the app and click Check.

1. Introduction

Research on effort tracking has a long history (Smith 2020; Brown and Lee 2019). Earlier work focused on time sheets (Nguyen 2025), while more recent studies look at cognitive load (Garcia et al. 2021). According to Liesenfeld and Dingemanse (2024), open models make replication easier, a point Öqvist (2022) also makes.

Several authors disagree (Smith & Jones 2020). Others report mixed results (Patel, 2018), and a few studies are still in press (Kowalski 2023a).

2. Method

We followed the protocol of Smith (2020) and the coding scheme in Brown and Lee (2019). The Treaty was signed (2019), which is not a citation. Data were collected over twelve weeks (see Table 1).

3. Discussion

As Garcia et al. (2021) note, workload is subjective. The findings agree with Mähring and Pries-Heje (2017).

References

Adams Z (2015). “An entry nobody cites”. Journal of Things, 1(1):1-5
Brown C and Lee D (2019) Counting what counts. Journal of Measurement (8:1):5-9
Garcia M, Ito K & Novak P (2021). “Cognitive load at work”. Ergonomics Quarterly, 33(2):101-120
Hobbes T (1651) Leviathan or The Matter, Forme and Power of a Commonwealth. Project Gutenberg
Kowalski T (2023a). “Notes on in-press work”. Journal of Things, 4(2):1-9
Liesenfeld A & Dingemanse M (2024). “Rethinking open source generative AI”. Proceedings of FAccT, 7(1):1-14
Mähring M & Pries-Heje J (2017). “Projects as journeys”. In: Kowal R (ed) The Big Book of Projects. Wiley, Hoboken
Öqvist L (2022). Open science in practice. University Press, Uppsala
Smith A (2020). “Effort and its discontents”. Journal of Workload Studies, 12(3):45-67
Patel R (2018). “A study that is cited”. Journal of Things, 2(1):10-20

Appendix A

The coding manual draws on Hobbes (1651).
"""

final class ParsingTests: XCTestCase {
    func testCitationKeys() {
        XCTAssertEqual(citationKeys("Smith & Jones, 2026"),
                       [CitationKey(author: "Smith", year: "2026"), CitationKey(author: "Jones", year: "2026")])
        XCTAssertEqual(citationKeys("Garcia et al. 2021"), [CitationKey(author: "Garcia", year: "2021")])
        XCTAssertEqual(citationKeys("Kowalski 2023a"), [CitationKey(author: "Kowalski", year: "2023")])
        XCTAssertEqual(citationKeys("Mähring and Pries-Heje 2017"),
                       [CitationKey(author: "Mähring", year: "2017"), CitationKey(author: "Pries-Heje", year: "2017")])
        XCTAssertEqual(citationKeys("see Table 1"), [])
    }

    func testReferenceKeysAndParts() {
        XCTAssertEqual(referenceKeys("Smith, J. (2026). A study of things. Journal of Things."),
                       [CitationKey(author: "Smith", year: "2026")])
        // An initial is not a surname.
        XCTAssertEqual(referenceKeys("Mähring M & Pries-Heje J (2017). Title. Pub"),
                       [CitationKey(author: "Mähring", year: "2017"), CitationKey(author: "Pries-Heje", year: "2017")])
        XCTAssertEqual(referenceKeys("Brown B (2023, 23 May). A blog post."), [CitationKey(author: "Brown", year: "2023")])
        XCTAssertEqual(referenceAuthorPrefix("Smith A & Jones B (2020) Crime and punishment. Pub, City"), "Smith A & Jones B ")
        XCTAssertEqual(referencePostYear("Smith A (2020) A study. Journal of Things, 16(2):100-110"),
                       " A study. Journal of Things, 16(2):100-110")
        XCTAssertEqual(referencePostYear("No year here"), "")
    }

    func testReferenceTitle() {
        XCTAssertEqual(referenceTitle("Smith A (2026). \"A study of things\". Journal of Things", start: "\"", end: "\""),
                       "\"A study of things\"")
        XCTAssertEqual(referenceTitle("Smith A (2026). \u{201C}A study.\u{201D} Journal", start: "\u{201C}", end: "\u{201D}"),
                       "\u{201C}A study.\u{201D}")
        XCTAssertEqual(referenceTitle("Smith A (2026). A study of things. Journal of Things"), "A study of things")
    }

    func testNarrativeCitations() {
        let line = "As shown by Liesenfeld and Dingemanse (2024), this holds."
        let found = narrativeCitations(in: line)
        XCTAssertEqual(found.map(\.text), ["Liesenfeld and Dingemanse 2024"])
        XCTAssertEqual(NSString(string: line).substring(with: found[0].span.range), "Liesenfeld and Dingemanse (2024)")
        XCTAssertEqual(narrativeCitations(in: "the treaty was signed (2019)").map(\.text), [])
    }

    func testInlineCitations() {
        let line = "This is shown elsewhere (Smith, 2026; Jones 2024)."
        let found = inlineCitations(in: line, narrative: narrativeCitations(in: line))
        XCTAssertEqual(found.map(\.text), ["Smith, 2026", "Jones 2024"])
        let ns = NSString(string: line)
        XCTAssertEqual(found.map { ns.substring(with: $0.span.range) }, ["Smith, 2026", "Jones 2024"])
        // A year-only parenthesis is the year half of a narrative citation.
        let narrativeLine = "Smith (2020) said so [and more]."
        let all = inlineCitations(in: narrativeLine, narrative: narrativeCitations(in: narrativeLine))
        XCTAssertEqual(all.map(\.text), ["and more", "Smith 2020"])
        XCTAssertEqual(all.map(\.isNarrative), [false, true])
        XCTAssertEqual(inlineCitations(in: "Empty () and []", narrative: []).map(\.text), [])
        XCTAssertEqual(inlineCitations(in: "(Smith 2020)", narrative: [], whitelist: ["Smith 2020"]).map(\.text), [])
    }

    func testSourceLines() {
        let text = "  One \r\nTwo\rThree\u{2028}Four\n\n   \nFive  "
        let lines = sourceLines(of: text)
        XCTAssertEqual(lines.map(\.text), ["One", "Two", "Three", "Four", "Five"])
        let ns = NSString(string: text)
        for line in lines { XCTAssertEqual(ns.substring(with: line.span.range), line.text) }
    }

    func testSections() {
        let text = "Intro (Smith 2020).\n## 7. References\nSmith A (2020). T. J, 1(1)\nAppendix B\nMore (Jones 2021)."
        let doc = parseDocument(text)
        XCTAssertEqual(doc.references.map(\.text), ["Smith A (2020). T. J, 1(1)"])
        XCTAssertEqual(doc.citations.map(\.text), ["Smith 2020", "Jones 2021"])
        XCTAssertEqual(doc.referencesHeading.map { NSString(string: text).substring(with: $0.range) }, "## 7. References")
        XCTAssertEqual(doc.appendixHeading.map { NSString(string: text).substring(with: $0.range) }, "Appendix B")
    }

    func testPythonHelpers() {
        XCTAssertEqual("  a b \u{00A0}\u{2003}".pyStrip, "a b")
        XCTAssertEqual(" a ".pyLStrip, "a ")
        XCTAssertEqual(" a ".pyRStrip, " a")
        XCTAssertTrue("Z".pythonLess(than: "a"))
        XCTAssertTrue("ab".pythonLess(than: "abc"))
        XCTAssertFalse("b".pythonLess(than: "a"))
        XCTAssertEqual(foldToASCII("Öqvist"), "oqvist")
        XCTAssertEqual(foldToASCII("Bjørnsson"), "bjornsson")
        XCTAssertEqual(foldToASCII("Weiß"), "weiss")
    }
}

final class AnalysisTests: XCTestCase {
    func texts(_ report: CheckReport, _ kind: CheckKind) -> [String] {
        report.findings(kind).map(\.checkedText)
    }

    /// The Python checker's report on the sample, with the default style.
    func testSampleWithDefaultStyle() {
        let report = CitationChecker.check(sampleManuscript, style: .standard)
        let brown = "Brown C and Lee D (2019) Counting what counts. Journal of Measurement (8:1):5-9"
        XCTAssertEqual(texts(report, .missingReference), ["Nguyen 2025"])
        XCTAssertEqual(texts(report, .unusedReference),
                       ["Adams Z (2015). \u{201C}An entry nobody cites\u{201D}. Journal of Things, 1(1):1-5"])
        XCTAssertEqual(texts(report, .inTextComma), ["Patel, 2018"])
        XCTAssertEqual(texts(report, .referenceOrder),
                       ["Patel R (2018). \u{201C}A study that is cited\u{201D}. Journal of Things, 2(1):10-20"])
        XCTAssertEqual(texts(report, .inTextSeparator), ["Smith & Jones 2020"])
        XCTAssertEqual(texts(report, .referenceSeparator), [brown])
        XCTAssertEqual(texts(report, .volumeIssue), [brown])
        XCTAssertEqual(texts(report, .titleSymbols), [brown])
        XCTAssertEqual(report.referenceCount, 10)
        XCTAssertEqual(report.issueCount, 8)
    }

    /// The Python checker's report on the sample, with every setting changed.
    func testSampleWithOtherStyle() {
        let style = CitationStyle(usesCommaInText: true, inTextSeparator: .ampersand, referenceSeparator: .and,
                                  volumeIssueFormat: .parenthetical, titleStart: "", titleEnd: "")
        let report = CitationChecker.check(sampleManuscript, style: style)
        XCTAssertEqual(texts(report, .inTextComma),
                       ["Garcia et al. 2021", "Kowalski 2023a", "Nguyen 2025", "Smith & Jones 2020"])
        XCTAssertEqual(texts(report, .inTextSeparator),
                       ["Brown and Lee 2019", "Liesenfeld and Dingemanse 2024", "Mähring and Pries-Heje 2017"])
        XCTAssertEqual(report.findings(.referenceSeparator).map { String($0.checkedText.prefix(6)) },
                       ["Garcia", "Liesen", "Mährin"])
        XCTAssertEqual(report.findings(.volumeIssue).map { String($0.checkedText.prefix(5)) },
                       ["Adams", "Garci", "Kowal", "Liese", "Smith", "Patel"])
        XCTAssertTrue(report.isSkipped(.titleSymbols))
        XCTAssertEqual(texts(report, .titleSymbols), [])
    }

    func testFindingsPointAtTheText() {
        let report = CitationChecker.check(sampleManuscript, style: .standard)
        let ns = NSString(string: sampleManuscript)
        let missing = report.findings(.missingReference)[0]
        XCTAssertEqual(missing.text, "(Nguyen 2025)")
        XCTAssertEqual(missing.detail, "No reference by Nguyen from 2025")
        XCTAssertEqual(missing.occurrences.compactMap { $0 }.map { ns.substring(with: $0.range) }, ["Nguyen 2025"])
        let separator = CitationChecker.check(sampleManuscript, style: CitationStyle(inTextSeparator: .ampersand))
        let liesenfeld = separator.findings(.inTextSeparator).first { $0.checkedText.hasPrefix("Liesenfeld") }
        XCTAssertEqual(liesenfeld?.text, "Liesenfeld and Dingemanse (2024)")
        XCTAssertEqual((liesenfeld?.occurrences.first??.range).map { ns.substring(with: $0) },
                       "Liesenfeld and Dingemanse (2024)")
        let unused = report.findings(.unusedReference)[0]
        XCTAssertEqual((unused.occurrences.first??.range).map { ns.substring(with: $0) }, unused.text)
        XCTAssertEqual(report.findings(.inTextComma)[0].detail, "Expected (Patel 2018)")
    }

    func testCommaCorrection() {
        XCTAssertEqual(inTextStyleCorrection("Jones 2024", usesComma: true), "Jones, 2024")
        XCTAssertEqual(inTextStyleCorrection("Smith,2026", usesComma: false), "Smith 2026")
        XCTAssertTrue(matchesInTextStyle("Smith, 2026", usesComma: true))
        XCTAssertFalse(matchesInTextStyle("Jones 2024", usesComma: true))
        XCTAssertTrue(matchesInTextStyle("no year", usesComma: true))
    }

    func testOrderFoldsAccents() {
        let text = "References\nMähring M (2017). T. J, 1(1)\nÖqvist L (2022). T. J, 1(1)\nPatel R (2018). T. J, 1(1)"
        XCTAssertEqual(CitationChecker.check(text, style: .standard).findings(.referenceOrder).count, 0)
    }

    func testVolumeIssueStrayComma() {
        let text = "References\nSmith A (2020). \u{201C}T\u{201D}. Journal of Things, (16:2)"
        let style = CitationStyle(volumeIssueFormat: .parenthetical)
        let found = CitationChecker.check(text, style: style).findings(.volumeIssue)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.detail, "No comma before the volume: Journal (16:2)")
    }

    func testBooksAreNotTitleChecked() {
        let text = "References\nHobbes T (1651) Leviathan or The Matter. Project Gutenberg"
        XCTAssertEqual(CitationChecker.check(text, style: .standard).findings(.titleSymbols).count, 0)
    }

    func testEditsMoveAndDropSpans() {
        let text = "Intro (Nguyen 2025) and (Doe 2001).\nReferences\nSmith A (2020). T. J, 1(1)"
        var report = CitationChecker.check(text, style: .standard)
        let before = report.findings(.missingReference).map { $0.occurrences.first! }
        XCTAssertEqual(before.count, 2)
        // Insert three characters at the start: every span moves by three.
        report.applyEdit(at: 0, replaced: 0, inserted: 3)
        XCTAssertEqual(report.findings(.missingReference).map { finding in finding.occurrences.first!?.location },
                       before.map { span in span.map { $0.location + 3 } })
        // Replace part of "Doe 2001": that occurrence is gone.
        let doe = report.findings(.missingReference).first { $0.checkedText == "Doe 2001" }!.occurrences.first!!
        report.applyEdit(at: doe.location + 1, replaced: 2, inserted: 5)
        XCTAssertTrue(report.findings(.missingReference).first { $0.checkedText == "Doe 2001" }!.isGone)
        XCTAssertFalse(report.findings(.missingReference).first { $0.checkedText == "Nguyen 2025" }!.isGone)
    }

    func testNoReferencesHeading() {
        let report = CitationChecker.check("Just text (Smith 2020).", style: .standard)
        XCTAssertNil(report.referencesHeading)
        XCTAssertEqual(report.referenceCount, 0)
        XCTAssertEqual(report.findings(.missingReference).count, 1)
    }
}

final class StyleTests: XCTestCase {
    func testDefaultsMatchThePythonChecker() {
        let s = CitationStyle.standard
        XCTAssertFalse(s.usesCommaInText)
        XCTAssertEqual(s.inTextSeparator, .and)
        XCTAssertEqual(s.referenceSeparator, .ampersand)
        XCTAssertEqual(s.volumeIssueFormat, .comma)
        XCTAssertEqual(s.titleStart, "\u{201C}")
        XCTAssertEqual(s.titleEnd, "\u{201D}")
    }

    func testCodableToleratesMissingKeys() throws {
        let decoded = try JSONDecoder().decode(CitationStyle.self, from: Data(#"{"usesCommaInText": true}"#.utf8))
        XCTAssertTrue(decoded.usesCommaInText)
        XCTAssertEqual(decoded.titleStart, CitationStyle.standard.titleStart)
        var style = CitationStyle(volumeIssueFormat: .parenthetical)
        style.titleStart = "\u{00AB}"
        let round = try JSONDecoder().decode(CitationStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(round, style)
    }

    func testExamplesAndSymbols() {
        XCTAssertEqual(CitationStyle.standard.inTextExample, "(Smith and Jones 2026)")
        XCTAssertEqual(CitationStyle(usesCommaInText: true, inTextSeparator: .ampersand).inTextExample,
                       "(Smith & Jones, 2026)")
        XCTAssertEqual(TitleSymbols.matching(.standard)?.name, "Curly double quotes")
        XCTAssertEqual(TitleSymbols.matching(CitationStyle(titleStart: "", titleEnd: "")), TitleSymbols.noSymbols)
        XCTAssertNil(TitleSymbols.matching(CitationStyle(titleStart: "<", titleEnd: ">")))
    }
}
