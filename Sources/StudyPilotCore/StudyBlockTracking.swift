import Foundation

/// Stored in event notes so completion survives backups and calendar synchronization.
public struct StudyBlockTracking: Codable, Equatable, Sendable {
    public var deadline: Date?
    public var completedAt: Date?
    public var previousStart: Date?
    public init(deadline: Date? = nil, completedAt: Date? = nil, previousStart: Date? = nil) {
        self.deadline = deadline; self.completedAt = completedAt; self.previousStart = previousStart
    }
    private static let prefix = "StudyPilot-Progress: "
    public static func read(_ notes: String) -> Self {
        guard let line = notes.components(separatedBy: "\n").first(where: { $0.hasPrefix(prefix) }), line.count < 4096,
              let data = Data(base64Encoded: String(line.dropFirst(prefix.count))),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    public func writing(to notes: String) -> String {
        var lines = notes.components(separatedBy: "\n").filter { !$0.hasPrefix(Self.prefix) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(self)) ?? Data()
        lines.insert(Self.prefix + encoded.base64EncodedString(), at: min(1, lines.count))
        return lines.joined(separator: "\n")
    }
    public static func isUnfinished(start: Date, minutes: Int, notes: String, now: Date) -> Bool {
        PlannedStudyBlock.taskID(in: notes) != nil && read(notes).completedAt == nil && start.addingTimeInterval(Double(minutes) * 60) <= now
    }
    /// Move the existing block intact. Never accept a partial allocation or change its deadline.
    public static func nextStart(minutes: Int, deadline: Date, busy: [PlanningBusyTime], preferences: PlanningPreferences, now: Date, calendar: Calendar = .current) throws -> Date? {
        guard (5...120).contains(minutes) else { return nil }
        var p = preferences; p.sessionMinutes = max(15, minutes)
        let task = PlanningTask(id: "reschedule:" + UUID().uuidString, title: "Unfinished study", deadline: deadline, minutes: minutes)
        let result = try StudyPlanner.makePlan(tasks: [task], busy: busy, preferences: p, now: now.addingTimeInterval(1), calendar: calendar, minimumBlockMinutes: minutes)
        guard result.blocks.count == 1, let block = result.blocks.first, block.minutes == minutes else { return nil }
        return block.start
    }
}
