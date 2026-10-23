import SwiftUI
import Combine
import Sparkle

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published var canCheck = false
    @Published var sessionInProgress = false
    @Published private(set) var preparingCheck = false
    var isBusy: Bool { sessionInProgress || preparingCheck }
    private let controller: SPUStandardUpdaterController
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.sessionInProgress).receive(on: RunLoop.main).assign(to: &$sessionInProgress)
    }
    private var hasBlockingSheet: Bool {
        NSApp.modalWindow?.isVisible == true || NSApp.windows.contains {
            $0.isVisible && $0.attachedSheet?.isVisible == true
        }
    }
    func checkAfterSettingsCloses() async -> String? {
        guard !preparingCheck else { return nil }
        preparingCheck = true
        defer { preparingCheck = false }
        // SwiftUI's onDismiss can precede AppKit detaching the animated sheet.
        // Wait for the actual window state, with a finite timeout and no forced close.
        for _ in 0..<40 {
            if !hasBlockingSheet { return check() }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return nil }
        }
        return "The dialog is still closing. Please try Check for Updates again from the StudyPilot menu."
    }
    @discardableResult func check() -> String? {
        guard controller.updater.canCheckForUpdates else { return nil }
        guard !hasBlockingSheet else {
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
            .disabled(!updater.canCheck || updater.preparingCheck || focus.state != nil)
    }
}
