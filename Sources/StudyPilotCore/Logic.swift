import Foundation

public enum TaskStatus: String, CaseIterable, Codable, Sendable {
    case todo = "To do", inProgress = "In progress", done = "Done"
}
public enum ReviewRating: String, CaseIterable, Codable, Sendable {
    case again = "Again", hard = "Hard", good = "Good", easy = "Easy"
}
public enum Criterion: String, CaseIterable, Identifiable, Sendable {
    case a = "A", b = "B", c = "C", d = "D"
    public var id: String { rawValue }
    public func score(in result: AssessmentRecord) -> Int? {
        switch self {
        case .a: result.criterionA
        case .b: result.criterionB
        case .c: result.criterionC
        case .d: result.criterionD
        }
    }
}
public enum PlannerLogic {
    public static func isOverdue(_ task: AssignmentRecord, at now: Date) -> Bool {
        task.status != TaskStatus.done.rawValue && task.dueDate < now
    }
    public static func progress(_ task: AssignmentRecord) -> Double {
        if task.status == TaskStatus.done.rawValue { return 1 }
        guard !task.checklist.isEmpty else { return 0 }
        return Double(task.checklist.filter(\.isComplete).count) / Double(task.checklist.count)
    }
    public static func reschedule(_ task: AssignmentRecord, to day: Date, calendar: Calendar = .current) -> AssignmentRecord {
        var copy = task
        let time = calendar.dateComponents([.hour, .minute, .second], from: task.dueDate)
        let newDate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
        if let reminder = copy.reminderDate { copy.reminderDate = reminder.addingTimeInterval(newDate.timeIntervalSince(copy.dueDate)) }
        copy.dueDate = newDate
        return copy
    }
}

/// A deterministic, deliberately small SM-2-inspired scheduler. Dates are injected for tests.
public enum ReviewScheduler {
    public static func schedule(_ card: FlashcardRecord, rating: ReviewRating, now: Date, calendar: Calendar = .current) -> FlashcardRecord {
        var next = card
        let interval = Double(max(0, min(card.intervalDays, 36_500)))
        let ease = max(1.3, min(card.ease, 3.0))
        switch rating {
        case .again:
            next.repetitions = 0; next.intervalDays = 0; next.lapses += 1
            next.ease = max(1.3, ease - 0.2)
            next.dueDate = now.addingTimeInterval(600)
            return next
        case .hard:
            next.intervalDays = max(1, Int((interval * 1.2).rounded()))
            next.ease = max(1.3, ease - 0.15)
        case .good:
            next.intervalDays = card.repetitions == 0 ? 1 : card.repetitions == 1 ? 3 : max(1, Int((interval * ease).rounded()))
            next.ease = ease
        case .easy:
            next.intervalDays = card.repetitions == 0 ? 4 : max(4, Int((interval * ease * 1.3).rounded()))
            next.ease = min(3.0, ease + 0.15)
        }
        next.intervalDays = min(36_500, next.intervalDays)
        next.repetitions += 1
        next.dueDate = calendar.date(byAdding: .day, value: next.intervalDays, to: now) ?? now.addingTimeInterval(Double(next.intervalDays) * 86_400)
        return next
    }
    public static func accuracy(_ reviews: [ReviewRecord]) -> Double? {
        guard !reviews.isEmpty else { return nil }
        return Double(reviews.filter { $0.rating != ReviewRating.again.rawValue }.count) / Double(reviews.count)
    }
}

public struct FocusState: Codable, Equatable, Sendable {
    public var id: UUID
    public var subjectID: UUID?
    public var startedAt: Date
    public var plannedSeconds: Double
    public var remainingAtAnchor: Double
    public var anchorDate: Date?
    public var isBreak: Bool
    public init(id: UUID = UUID(), subjectID: UUID?, seconds: Double, now: Date, isBreak: Bool = false) {
        self.id = id; self.subjectID = subjectID; self.startedAt = now
        self.plannedSeconds = max(60, min(seconds, 14_400)); self.remainingAtAnchor = self.plannedSeconds
        self.anchorDate = now; self.isBreak = isBreak
    }
    public func remaining(at now: Date) -> Double {
        guard let anchorDate else { return remainingAtAnchor }
        return max(0, remainingAtAnchor - max(0, now.timeIntervalSince(anchorDate)))
    }
    public func elapsed(at now: Date) -> Double { max(0, plannedSeconds - remaining(at: now)) }
    public var completionDate: Date? { anchorDate?.addingTimeInterval(remainingAtAnchor) }
    public mutating func pause(at now: Date) { remainingAtAnchor = remaining(at: now); anchorDate = nil }
    public mutating func resume(at now: Date) { if anchorDate == nil { anchorDate = now } }
}

public enum StudyAnalytics {
    /// A qualifying day contains at least one recorded focus session of one minute.
    public static func streak(sessions: [StudySessionRecord], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(sessions.filter { $0.durationSeconds >= 60 }.map { calendar.startOfDay(for: $0.endedAt) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous != cursor else { break }
            cursor = previous
        }
        return count
    }
    public static func average(_ criterion: Criterion, assessments: [AssessmentRecord]) -> Double? {
        let scores = assessments.compactMap { criterion.score(in: $0) }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
}

public enum NoteLinks {
    public static func titles(in body: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#) else { return [] }
        let source = body as NSString
        return Array(Set(regex.matches(in: body, range: NSRange(location: 0, length: source.length)).map {
            source.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        })).sorted()
    }
}
