import SwiftUI
import Combine
import Sparkle

private final class UpdateFeedReader: NSObject, XMLParserDelegate {
    var build: Int?
    var version: String?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard name == "enclosure", build == nil else { return }
        build = Int(attributes["sparkle:version"] ?? "")
        version = attributes["sparkle:shortVersionString"]
    }
}

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published var canCheck = false
    @Published var sessionInProgress = false
    @Published private(set) var preparingCheck = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastAvailabilityCheck: Date?
    @Published private(set) var availabilityError: String?
    private var lastAvailabilityAttempt: Date?
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
    func refreshAvailability() async {
        if let attempt = lastAvailabilityAttempt, Date().timeIntervalSince(attempt) < 3_600 { return }
        lastAvailabilityAttempt = Date()
        guard let url = URL(string: "https://raw.githubusercontent.com/Sumi1124/StudyPilot/main/updates/appcast.xml") else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let reader = UpdateFeedReader()
            let parser = XMLParser(data: data)
            parser.delegate = reader
            guard parser.parse(), let build = reader.build, let version = reader.version else { throw URLError(.cannotParseResponse) }
            let installed = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
            availableVersion = build > installed ? version : nil
            lastAvailabilityCheck = Date()
            availabilityError = nil
        } catch { availabilityError = "Could not check for updates right now." }
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
