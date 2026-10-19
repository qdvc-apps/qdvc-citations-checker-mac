import CitationsCore
import SwiftUI

/// The inspector on the right of the window (⌥⌘I): the citation style the
/// manuscript is checked against. Changes apply at the next check.
struct StyleInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Year", selection: $model.style.usesCommaInText) {
                    Text("(Smith 2026)").tag(false)
                    Text("(Smith, 2026)").tag(true)
                }
                Picker("Last author", selection: $model.style.inTextSeparator) {
                    Text("Smith and Jones").tag(AuthorSeparator.and)
                    Text("Smith & Jones").tag(AuthorSeparator.ampersand)
                }
            } header: {
                Text("In-text Citations")
            } footer: {
                ExampleText(text: model.style.inTextExample)
            }

            Section {
                Picker("Last author", selection: $model.style.referenceSeparator) {
                    Text("Smith A and Jones B").tag(AuthorSeparator.and)
                    Text("Smith A & Jones B").tag(AuthorSeparator.ampersand)
                }
                Picker("Volume and issue", selection: $model.style.volumeIssueFormat) {
                    ForEach(VolumeIssueFormat.allCases) { format in
                        Text(format.example).tag(format)
                    }
                }
                TitleSymbolsPicker()
            } header: {
                Text("Reference List")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    ExampleText(text: model.style.referenceExample)
                    Text("Titles are checked for journal articles and book chapters only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restore Defaults") { model.style = .standard }
                    .disabled(model.style == .standard)
            } footer: {
                if model.styleChangedSinceCheck {
                    Text("Check again (\u{2318}R) to apply the changes.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Changes apply the next time you check (\u{2318}R).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// An example in the current style, under a section.
struct ExampleText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Example: \(text)")
    }
}

/// The symbols around a reference's title: common pairs, or a custom pair
/// typed in.
struct TitleSymbolsPicker: View {
    @Environment(AppModel.self) private var model
    /// Custom chosen while the fields still hold a common pair.
    @State private var customChosen = false

    private static let customID = "custom"

    var body: some View {
        @Bindable var model = model
        let common = TitleSymbols.matching(model.style)
        let showsFields = customChosen || common == nil
        Picker("Title symbols", selection: Binding<String>(
            get: { showsFields ? Self.customID : (common?.id ?? Self.customID) },
            set: { id in
                if id == Self.customID {
                    customChosen = true
                } else if let pair = TitleSymbols.common.first(where: { $0.id == id }) {
                    customChosen = false
                    model.style.titleStart = pair.start
                    model.style.titleEnd = pair.end
                }
            }
        )) {
            ForEach(TitleSymbols.common) { pair in
                Text(pair == TitleSymbols.noSymbols ? "None (not checked)" : "\(pair.sample)  \(pair.name)")
                    .tag(pair.id)
            }
            Divider()
            Text("Custom").tag(Self.customID)
        }
        if showsFields {
            TextField("Starts with", text: $model.style.titleStart)
                .font(.body.monospaced())
            TextField("Ends with", text: $model.style.titleEnd)
                .font(.body.monospaced())
        }
    }
}
