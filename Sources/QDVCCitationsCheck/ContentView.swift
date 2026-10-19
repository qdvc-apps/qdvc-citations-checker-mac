import CitationsCore
import SwiftUI

/// The window: the issue navigator on the left, the manuscript in the
/// middle, and the citation style in the inspector on the right, as in
/// Xcode (navigator, editor, inspector).
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            IssueNavigator()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 460)
        } detail: {
            ManuscriptPane()
        }
        .inspector(isPresented: $model.inspectorShown) {
            StyleInspector()
                .inspectorColumnWidth(min: 250, ideal: 290, max: 400)
        }
        .navigationTitle("QDVC Citations Check")
        .navigationSubtitle(model.statusText)
        .toolbar { MainToolbar(model: model).content }
    }
}

/// The manuscript, with a hint while it is empty.
struct ManuscriptPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ManuscriptEditor(model: model)
            .overlay(alignment: .topLeading) {
                if model.isTextEmpty {
                    EditorPlaceholder(size: model.fontSize)
                        // The text container's inset plus its 5 pt line padding.
                        .padding(.leading, ManuscriptEditor.inset.width + 5)
                        .padding(.top, ManuscriptEditor.inset.height)
                        .padding(.trailing, ManuscriptEditor.inset.width)
                        .allowsHitTesting(false)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
    }
}

struct EditorPlaceholder: View {
    var size: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste your paper here")
                .font(.system(size: size))
                .foregroundStyle(.tertiary)
            Text("Plain text from your word processor is fine. Start the reference list with a line that begins with \u{201C}References\u{201D}, and any appendix with a line that begins with \u{201C}Appendix\u{201D}. Nothing you paste is saved.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The window's toolbar. Every item is also in the menu bar.
@MainActor
struct MainToolbar {
    @Bindable var model: AppModel

    @ToolbarContentBuilder
    var content: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.check()
            } label: {
                Label("Check", systemImage: "checkmark.seal")
            }
            .labelStyle(.titleAndIcon)
            .help("Check the citations against the style in the inspector (\u{2318}R)")
            .disabled(model.isTextEmpty)

            ControlGroup {
                Button {
                    model.step(-1)
                } label: {
                    Label("Previous Issue", systemImage: "chevron.up")
                }
                .help("Previous issue (\u{21E7}\u{2318}')")
                Button {
                    model.step(1)
                } label: {
                    Label("Next Issue", systemImage: "chevron.down")
                }
                .help("Next issue (\u{2318}')")
            } label: {
                Label("Issues", systemImage: "chevron.up.chevron.down")
            }
            .disabled(!model.hasIssues)

            Button {
                model.inspectorShown.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the citation style (\u{2325}\u{2318}I)")
        }
    }
}
