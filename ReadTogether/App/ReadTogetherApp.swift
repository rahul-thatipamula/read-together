import SwiftUI

@main
struct ReadTogetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    delegate.state = state
                    if SelfTest.requested { Task { await SelfTest.run(state) } }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Book…") { state.importPDF() }.keyboardShortcut("o")
            }
            CommandMenu("Reading") {
                Button(state.focusMode ? "Exit Focus Mode" : "Focus Mode") { state.focusMode.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(state.activeBook == nil)
                Button(state.chatOpen ? "Hide Chat" : "Show Chat") { state.chatOpen.toggle() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Marks") { state.showMarks.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(state.activeBook == nil)
            }
        }
    }
}

/// Frees the model on quit so nothing lingers in memory.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        Task { @MainActor in
            await state.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
