import Foundation
import SwiftData
import StudyPilotCore
import StudyPilotData

@MainActor enum BackupService {
    static func directory(_ context: ModelContext) throws -> URL {
        guard let configuration = context.container.configurations.first else { throw BackupError.invalid("The database location is unavailable.") }
        let url = configuration.url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func files(_ context: ModelContext) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory(context), includingPropertiesForKeys: [.creationDateKey]).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    @discardableResult static func create(_ context: ModelContext, prefix: String = "manual") throws -> URL {
        let data = try BackupCodec.encode(BackupStore.snapshot(context))
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = try directory(context).appendingPathComponent("\(timestamp)-\(prefix)-\(UUID().uuidString.prefix(6)).json")
        try data.write(to: url, options: [.atomic])
        return url
    }
    static func automatic(_ context: ModelContext) throws {
        let existing = try files(context)
        let todayExists = existing.contains { file in
            guard file.lastPathComponent.contains("-automatic-"), let values = try? file.resourceValues(forKeys: [.creationDateKey]), let date = values.creationDate else { return false }
            return Calendar.current.isDateInToday(date)
        }
        if !todayExists { try create(context, prefix: "automatic") }
    }
    static func read(_ url: URL) throws -> BackupEnvelope {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= BackupCodec.maximumBytes else { throw BackupError.invalid("Choose a JSON backup file smaller than 50 MB.") }
        return try BackupCodec.decode(Data(contentsOf: url))
    }
}
