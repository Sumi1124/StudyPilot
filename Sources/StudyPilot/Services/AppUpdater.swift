import SwiftUI
import Combine
import Sparkle

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published var canCheck = false
    private let controller: SPUStandardUpdaterController
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
    }
    func check() { controller.checkForUpdates(nil) }
}

struct AppUpdateButton: View {
    @ObservedObject private var updater = AppUpdater.shared
    @Environment(FocusController.self) private var focus
    var body: some View {
        Button("Check for Updates…", systemImage: "arrow.down.circle") { updater.check() }
            .disabled(!updater.canCheck || focus.state != nil)
    }
}
