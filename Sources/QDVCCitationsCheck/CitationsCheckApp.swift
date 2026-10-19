import AppKit
import CitationsCore
import SwiftUI

@main
struct CitationsCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        // Nothing pasted is kept, so there is no window state worth restoring.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    var body: some Scene {
        // One window: paste, check, fix, check again.
        Window("QDVC Citations Check", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 460)
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CitationsCommands(model: model)
            SidebarCommands()
            TextEditingCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct CitationsCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // There is nothing to create or open: the text is pasted in.
        CommandGroup(replacing: .newItem) {}

        // The only settings are the citation style, in the inspector.
        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") { model.inspectorShown = true }
                .keyboardShortcut(",")
        }

        CommandMenu("Check") {
            Button("Check Citations") { model.check() }
                .keyboardShortcut("r")
                .disabled(model.isTextEmpty)
            Divider()
            Button("Next Issue") { model.step(1) }
                .keyboardShortcut("'")
                .disabled(!model.hasIssues)
            Button("Previous Issue") { model.step(-1) }
                .keyboardShortcut("'", modifiers: [.command, .shift])
                .disabled(!model.hasIssues)
            Divider()
            Toggle("Underline Issues in Text", isOn: Binding(get: { model.underlineIssues },
                                                             set: { model.underlineIssues = $0 }))
            Divider()
            Button("Restore Default Style") { model.style = .standard }
                .disabled(model.style == .standard)
        }

        CommandGroup(after: .toolbar) {
            Button(model.inspectorShown ? "Hide Inspector" : "Show Inspector") { model.inspectorShown.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button("Zoom In") { model.zoom(1) }
                .keyboardShortcut("+")
            Button("Zoom Out") { model.zoom(-1) }
                .keyboardShortcut("-")
            Button("Actual Size") { model.zoom(0) }
                .keyboardShortcut("0")
            Divider()
        }
    }
}
