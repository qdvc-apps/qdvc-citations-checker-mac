import CitationsCore
import SwiftUI

/// The sidebar: the last check's findings, one section per check, like
/// Xcode's issue navigator. Selecting a finding selects it in the text.
struct IssueNavigator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let report = model.report {
                List(selection: $model.selection) {
                    SummarySection(report: report)
                    ForEach(CheckKind.allCases) { kind in
                        CheckSection(kind: kind, report: report)
                    }
                }
                .listStyle(.sidebar)
            } else {
                NotCheckedView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.isStale {
                StaleBanner()
            }
        }
    }
}

/// Before the first check (or after the text was cleared).
struct NotCheckedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Not Checked Yet", systemImage: "text.badge.checkmark")
        } description: {
            Text(model.isTextEmpty
                 ? "Paste your paper into the text area, then click Check (\u{2318}R)."
                 : "Click Check (\u{2318}R) to check the citations against the style in the inspector.")
        } actions: {
            Button("Check") { model.check() }
                .disabled(model.isTextEmpty)
        }
    }
}

/// Shown above the findings when they no longer describe the text or the
/// style.
struct StaleBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                Text(model.staleReason)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Check Again") { model.check() }
                    .controlSize(.small)
                    .disabled(model.isTextEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            Divider()
        }
    }
}

/// Counts, the overall result, and where the reference list starts.
struct SummarySection: View {
    let report: CheckReport

    var body: some View {
        Section("Summary") {
            let n = report.issueCount
            Label {
                Text(n == 0 ? "No issues found" : "\(n) issue\(n == 1 ? "" : "s") found")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: n == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(n == 0 ? Color.green : Color.orange)
            }
            Label {
                Text("\(report.citationCount) cited work\(report.citationCount == 1 ? "" : "s"), "
                     + "\(report.referenceCount) reference\(report.referenceCount == 1 ? "" : "s")")
            } icon: {
                Image(systemName: "text.quote")
            }
            .foregroundStyle(.secondary)
            .help("\(report.citationOccurrenceCount) in-text citation\(report.citationOccurrenceCount == 1 ? "" : "s") "
                  + "of \(report.citationCount) distinct work\(report.citationCount == 1 ? "" : "s")")

            if report.referencesHeading != nil {
                Label("Reference List", systemImage: "list.bullet.rectangle")
                    .help("Where the reference list starts")
                    .tag(NavigatorItem.referencesHeading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label("No References heading", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Every line was read as body text. Start the reference list with a line that begins with \u{201C}References\u{201D}.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if report.appendixHeading != nil {
                Label("Appendix", systemImage: "doc.append")
                    .help("Where the first appendix starts; its citations are checked too")
                    .tag(NavigatorItem.appendixHeading)
            }
        }
    }
}

/// One check: its findings, or a line saying it passed (or was skipped).
struct CheckSection: View {
    let kind: CheckKind
    let report: CheckReport

    var body: some View {
        let findings = report.findings(kind)
        Section {
            if report.isSkipped(kind) {
                Label("Skipped: no title symbols set", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            } else if findings.isEmpty {
                Label {
                    Text(kind.passMessage)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                ForEach(findings) { finding in
                    FindingRow(finding: finding)
                        .tag(NavigatorItem.finding(finding.id))
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("\(kind.rawValue). \(kind.title)")
                if !findings.isEmpty {
                    Text("\(findings.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .help(kind.explanation(for: report.style))
        }
    }
}

/// A citation or reference with a problem.
struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        let count = finding.occurrences.count
        let isSelected = model.selection == .finding(finding.id)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: finding.kind.isMatching ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(finding.kind.isMatching ? Color.red : Color.orange)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.text)
                    .lineLimit(finding.kind.isInText ? 1 : 2)
                    .truncationMode(.tail)
                if let detail = finding.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if finding.isGone {
                    Text("Edited since the check")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isSelected && count > 1 {
                    Text("Occurrence \(model.occurrenceIndex + 1) of \(count) \u{00B7} \u{2318}' for the next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(finding.isGone ? 0.55 : 1)
        .badge(count > 1 ? count : 0)
        .help(finding.detail.map { "\(finding.text)\n\($0)" } ?? finding.text)
        .contextMenu {
            Button("Show in Text") { model.show(.finding(finding.id)) }
                .disabled(finding.isGone)
        }
    }
}
