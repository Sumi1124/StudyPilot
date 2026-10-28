import Foundation
import Observation
import StudyPilotCore

@MainActor @Observable final class AIModelService {
    private(set) var choice = ChatModelChoice.saved(UserDefaults.standard.string(forKey: "chatModelChoice"))
    private(set) var ready = false
    private(set) var checking = false
    private(set) var downloading = false
    private(set) var reachable = false
    private(set) var status = "Check Ollama to use Qwen 3.5 0.8B."
    private(set) var fraction: Double?
    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?
    let client = OllamaClient()
    func select(_ value: ChatModelChoice) {
        choice = value; UserDefaults.standard.set(value.rawValue, forKey: "chatModelChoice")
    }
    func refresh() async {
        guard !checking, !downloading else { return }
        checking = true
        defer { checking = false }
        do {
            ready = try await client.isInstalled(); reachable = true
            status = ready ? "Qwen 3.5 0.8B is ready on this Mac." : "Ollama is running. Download Qwen 3.5 0.8B to use it."
        } catch {
            if Task.isCancelled { return }
            ready = false; reachable = false
            status = "Couldn’t reach Ollama at 127.0.0.1:11434. Start Ollama, then check again."
        }
    }
    func download() {
        guard !downloading, !checking, reachable else { return }
        let id = UUID(); downloadID = id; downloading = true; ready = false; fraction = nil; status = "Starting model download…"
        downloadTask = Task {
            defer { if downloadID == id { downloading = false; downloadTask = nil; downloadID = nil } }
            do {
                try await client.download { [weak self] item in
                    await self?.update(item, id: id)
                }
                guard !Task.isCancelled, downloadID == id else { return }
                ready = true; status = "Qwen 3.5 0.8B is ready on this Mac."; fraction = nil
            } catch {
                guard !Task.isCancelled, downloadID == id else { return }
                status = error.localizedDescription.contains("requires a newer version") ? "This model needs a newer Ollama version. Update Ollama, then download again." : error.localizedDescription; fraction = nil
            }
        }
    }
    private func update(_ item: OllamaWire.Progress, id: UUID) {
        guard downloadID == id else { return }
        fraction = item.fraction
        if let total = item.total, let completed = item.completed {
            status = "Downloading \(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        } else { status = item.status.map { String($0.prefix(150)) } ?? "Downloading…" }
    }
    func cancelDownload() {
        downloadID = nil; downloadTask?.cancel(); downloadTask = nil; downloading = false; fraction = nil
        status = "Download stopped. Download again to resume."
    }
    var unavailableReason: String? { ready && !downloading ? nil : status }
}
