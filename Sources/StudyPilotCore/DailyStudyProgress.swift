import Foundation

/// Study time follows the existing convention of crediting the session's ending day.
public struct DailyStudyProgress: Equatable, Sendable {
    public let seconds: Double
    public let goalMinutes: Int
    public var minutes: Int { Int(seconds / 60) }
    public var fraction: Double { min(1, seconds / Double(goalMinutes * 60)) }
    public var reachedGoal: Bool { seconds >= Double(goalMinutes * 60) }
    public var remainingMinutes: Int { max(0, Int(ceil((Double(goalMinutes * 60) - seconds) / 60))) }

    public init(sessions: [StudySessionRecord], goalMinutes: Int, now: Date, calendar: Calendar = .current) {
        self.goalMinutes = max(15, min(480, goalMinutes))
        seconds = sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: now) && $0.endedAt <= now }
            .reduce(0) { $0 + ($1.durationSeconds.isFinite ? max(0, $1.durationSeconds) : 0) }
    }
}
