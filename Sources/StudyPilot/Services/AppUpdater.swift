import SwiftUI
import Combine
import Sparkle

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published var canCheck = false
    @Published var sessionInProgress = false
    private let controller: SPUStandardUpdaterController
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.sessionInProgress).receive(on: RunLoop.main).assign(to: &$sessionInProgress)
    }
    @discardableResult func check() -> String? {
        guard controller.updater.canCheckForUpdates else { return nil }
        guard NSApp.modalWindow == nil, !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else {
            return "Close the open editor or dialog before checking for updates. Your draft has been kept open."
        }
        controller.checkForUpdates(nil)
        return nil
    }
}

struct AppUpdateButton: View {
    @ObservedObject private var updater = AppUpdater.shared
    @Environment(FocusController.self) private var focus
    @Environment(AppState.self) private var app
    var body: some View {
        Button("Check for Updates…", systemImage: "arrow.down.circle") {
            if app.showingSettings {
                // Start only from the sheet's onDismiss callback, after AppKit detaches it.
                app.checkForUpdatesAfterSettings = true
                app.showingSettings = false
            } else if let error = updater.check() {
                app.error = error
            }
        }
            .disabled(!updater.canCheck || focus.state != nil)
    }
}
