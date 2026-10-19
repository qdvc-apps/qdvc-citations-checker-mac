// swift-tools-version: 5.10
//
// QDVC Citations Check for macOS — a native app for checking the APA-style
// citations in a paper: paste the text of your manuscript, click Check, and
// see which in-text citations have no reference, which references are never
// cited, and where the citation style is inconsistent.
//
// A Swift edition of qdvc-apa-citations-check (Python). Nothing is stored
// but the citation-style settings; the pasted text is never written to disk.
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "CitationsCore", targets: ["CitationsCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation only, no AppKit/SwiftUI, unit-testable.
    .target(name: "CitationsCore"),
    .testTarget(
        name: "CitationsCoreTests",
        dependencies: ["CitationsCore"]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md).
products.insert(.executable(name: "QDVCCitationsCheck", targets: ["QDVCCitationsCheck"]), at: 0)
targets.insert(.executableTarget(name: "QDVCCitationsCheck", dependencies: ["CitationsCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCCitationsCheck",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
