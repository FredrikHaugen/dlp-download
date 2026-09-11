import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { await model.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

@main struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel?
    private let startupError: String?
    init() {
        do { _model = State(initialValue: try AppModel()); startupError = nil }
        catch { _model = State(initialValue: nil); startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let model {
                MainView(model: model)
                    .task { delegate.model = model; if !model.isReady { await model.start() } }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.activated() }
            } else {
                ContentUnavailableView("Harbor couldn’t start", systemImage: "exclamationmark.triangle", description: Text(startupError ?? "Reinstall the app and try again."))
                    .frame(width: 600, height: 380)
            }
        }
        .defaultSize(width: 1080, height: 740)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Download…") { model?.addLinks() }.keyboardShortcut("n").disabled(model?.isReady != true)
            }
        }
        Settings { if let model { SettingsView(model: model) } }
    }
}
