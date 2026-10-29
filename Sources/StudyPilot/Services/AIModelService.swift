import Foundation
import Observation
import CryptoKit
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
    private var server: Process?
    private var managedServer: Process?
    let client = OllamaClient()
    func select(_ value: ChatModelChoice) {
        choice = value; UserDefaults.standard.set(value.rawValue, forKey: "chatModelChoice")
    }
    func refresh() async {
        guard !checking, !downloading else { return }
        checking = true
        defer { checking = false }
        do {
            if ManagedOllamaRuntime.isInstalled { try await startManagedServer(id: nil) }
            ready = try await client.isInstalled(); reachable = true
            status = ready ? "Qwen 3.5 0.8B is ready on this Mac." : "Ollama is running. Download Qwen 3.5 0.8B to use it."
        } catch {
            if Task.isCancelled { return }
            ready = false; reachable = false
            status = "Local model service is stopped. Download will start it automatically."
        }
    }
    func download() {
        guard !downloading, !checking else { return }
        let id = UUID(); downloadID = id; downloading = true; ready = false; fraction = nil; status = "Starting model download…"
        downloadTask = Task {
            defer { if downloadID == id { downloading = false; downloadTask = nil; downloadID = nil } }
            do {
                try await ensureServer(id: id)
                try Task.checkCancellation()
                do {
                    try await pullModel(id: id)
                } catch {
                    guard error.localizedDescription.localizedCaseInsensitiveContains("requires a newer version") else { throw error }
                    status = "Downloading an updated local model engine…"
                    try await ManagedOllamaRuntime.install()
                    try await startManagedServer(id: id)
                    try await pullModel(id: id)
                }
                guard !Task.isCancelled, downloadID == id else { return }
                ready = true; status = "Qwen 3.5 0.8B is ready on this Mac."; fraction = nil
            } catch {
                guard !Task.isCancelled, downloadID == id else { return }
                status = error.localizedDescription.contains("requires a newer version") ? "This model needs a newer Ollama version. Update Ollama, then download again." : error.localizedDescription; fraction = nil
            }
        }
    }
    private func pullModel(id: UUID) async throws {
        try await client.download { [weak self] item in await self?.update(item, id: id) }
    }
    private func ensureServer(id: UUID) async throws {
        if ManagedOllamaRuntime.isInstalled { try await startManagedServer(id: id); return }
        if (try? await client.isInstalled()) != nil { reachable = true; return }
        guard let binary = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/MacOS/ollama"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            status = "Downloading the local model engine…"
            try await ManagedOllamaRuntime.install()
            try await startManagedServer(id: id)
            return
        }
        status = "Starting the local model service…"
        if server?.isRunning != true {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["OLLAMA_HOST"] = "127.0.0.1:11434"
            process.environment = environment
            try process.run()
            server = process
        }
        for _ in 0..<40 {
            try Task.checkCancellation()
            guard downloadID == id else { throw CancellationError() }
            if (try? await client.isInstalled()) != nil { reachable = true; return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw PlanningError.invalid("The local model service could not start. Check that Ollama is installed correctly, then try again.")
    }
    private func startManagedServer(id: UUID?) async throws {
        await client.useManagedRuntime()
        if (try? await client.isInstalled()) != nil { reachable = true; return }
        guard ManagedOllamaRuntime.isInstalled else { throw PlanningError.invalid("The local model engine is incomplete. Try Download again.") }
        status = "Starting the updated local model engine…"
        if managedServer?.isRunning != true {
            let process = Process()
            process.executableURL = ManagedOllamaRuntime.binaryURL
            process.arguments = ["serve"]
            process.currentDirectoryURL = ManagedOllamaRuntime.directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["OLLAMA_HOST"] = "127.0.0.1:11435"
            environment["OLLAMA_MODELS"] = ManagedOllamaRuntime.modelsDirectory.path
            process.environment = environment
            try process.run()
            managedServer = process
        }
        for _ in 0..<40 {
            try Task.checkCancellation()
            if let id, downloadID != id { throw CancellationError() }
            if (try? await client.isInstalled()) != nil { reachable = true; return }
            if managedServer?.isRunning == false { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw PlanningError.invalid("StudyPilot could not start the updated local model engine.")
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

private enum ManagedOllamaRuntime {
    static let version = "v0.40.12"
    static let digest = "1d1b4c2cf40d2a239f9b08a77384830800a8542c744a55f47247f9baf85b55d2"
    static let archiveURL = URL(string: "https://github.com/ollama/ollama/releases/download/v0.40.12/ollama-darwin.tgz")!
    static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StudyPilot/LocalModelRuntime", isDirectory: true) }
    static var directory: URL { root.appendingPathComponent(version, isDirectory: true) }
    static var binaryURL: URL { directory.appendingPathComponent("ollama") }
    static var modelsDirectory: URL { root.appendingPathComponent("models", isDirectory: true) }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binaryURL.path) }
    static func install() async throws {
        if isInstalled { return }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let (downloaded, response) = try await URLSession.shared.download(from: archiveURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PlanningError.invalid("The official local model engine download failed.")
        }
        var hash = SHA256()
        let handle = try FileHandle(forReadingFrom: downloaded)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { throw PlanningError.invalid("The local model engine did not pass its checksum check.") }
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", downloaded.path, "-C", staging.path]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        while tar.isRunning { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(200)) }
        guard tar.terminationStatus == 0, manager.isExecutableFile(atPath: staging.appendingPathComponent("ollama").path) else {
            throw PlanningError.invalid("The local model engine archive could not be unpacked.")
        }
        if !isInstalled { try manager.moveItem(at: staging, to: directory) }
    }
}
