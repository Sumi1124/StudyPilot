import Foundation

public struct PlanningTask: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var details: String
    public var deadline: Date
    public var minutes: Int
    public var priority: Int
    public var steps: [String]
    public var selected: Bool
    public init(id: String, title: String, details: String = "", deadline: Date, minutes: Int = 60, priority: Int = 1, steps: [String] = [], selected: Bool = true) {
        self.id = id; self.title = title; self.details = details; self.deadline = deadline
        self.minutes = minutes; self.priority = priority; self.steps = steps; self.selected = selected
    }
}

public struct PlanningPreferences: Codable, Equatable, Sendable {
    public var days = 14
    public var startMinute = 16 * 60
    public var endMinute = 20 * 60
    public var weekdays: Set<Int> = Set(1...7)
    public var sessionMinutes = 25
    public var breakMinutes = 5
    public var dailyMinutes = 120
    public init() {}
    public func validate() throws {
        guard (1...28).contains(days), (0..<1440).contains(startMinute), (1...1440).contains(endMinute),
              startMinute < endMinute, !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)),
              (15...120).contains(sessionMinutes), (0...30).contains(breakMinutes), (15...480).contains(dailyMinutes)
        else { throw PlanningError.invalid("Choose valid study hours, at least one day, and a daily limit between 15 and 480 minutes.") }
    }
}

public enum PlanningError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public struct PlanningBusyTime: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var taskID: String?
    public init(start: Date, end: Date, taskID: String? = nil) { self.start = start; self.end = end; self.taskID = taskID }
    public func overlaps(start otherStart: Date, end otherEnd: Date) -> Bool { start < otherEnd && end > otherStart }
}

public struct PlannedStudyBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let taskID: String
    public let title: String
    public let start: Date
    public let minutes: Int
    public let steps: [String]
    public var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
    public init(id: UUID = UUID(), taskID: String, title: String, start: Date, minutes: Int, steps: [String] = []) {
        self.id = id; self.taskID = taskID; self.title = title; self.start = start; self.minutes = minutes; self.steps = steps
    }
    public var notes: String {
        let encoded = Data(taskID.utf8).base64EncodedString()
        return "StudyPilot-Task-ID: \(encoded)\n\n" + (steps.isEmpty ? "Work on this assignment, then check your progress." : steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
    }
    public static func taskID(in notes: String) -> String? {
        guard let first = notes.components(separatedBy: .newlines).first, first.hasPrefix("StudyPilot-Task-ID: "),
              let data = Data(base64Encoded: String(first.dropFirst("StudyPilot-Task-ID: ".count))), let id = String(data: data, encoding: .utf8), !id.isEmpty else { return nil }
        return id
    }
}

public struct UnscheduledStudyWork: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let minutes: Int
    public let reason: String
}
public struct StudyPlan: Sendable {
    public var blocks: [PlannedStudyBlock]
    public var unscheduled: [UnscheduledStudyWork]
    public var alreadyPlannedMinutes: Int
}

public enum StudyPlanner {
    /// Deadline-first allocation. The clock/calendar are injected for repeatable scheduling tests.
    /// Existing linked future sessions count toward remaining work; past sessions never imply completion.
    public static func makePlan(tasks: [PlanningTask], busy: [PlanningBusyTime], preferences p: PlanningPreferences,
                                now: Date, calendar: Calendar = .current) throws -> StudyPlan {
        try p.validate()
        guard now.timeIntervalSince1970.isFinite, tasks.count <= 500, busy.count <= 20_000,
              Set(tasks.map(\.id)).count == tasks.count,
              tasks.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (5...2400).contains($0.minutes) && (0...2).contains($0.priority) && $0.deadline.timeIntervalSince1970.isFinite }),
              busy.allSatisfy({ $0.start.timeIntervalSince1970.isFinite && $0.end.timeIntervalSince1970.isFinite && $0.start < $0.end })
        else { throw PlanningError.invalid("The planning data contains invalid or excessive tasks or calendar intervals.") }
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: p.days, to: today)!
        var occupied = busy.filter { $0.end > now && $0.start < horizon }
        // Preserve recovery time after existing StudyPilot sessions as well as newly allocated sessions.
        occupied = occupied.map { PlanningBusyTime(start: $0.start, end: $0.end.addingTimeInterval($0.taskID == nil ? 0 : Double(p.breakMinutes * 60)), taskID: $0.taskID) }
        var usedByDay: [Date: Int] = [:]
        for existing in busy where existing.taskID != nil && existing.end > now && existing.start < horizon {
            var day = calendar.startOfDay(for: max(existing.start, today))
            while day < min(existing.end, horizon) {
                let next = calendar.date(byAdding: .day, value: 1, to: day)!
                usedByDay[day, default: 0] += max(0, Int(min(next, existing.end).timeIntervalSince(max(day, existing.start)) / 60))
                day = next
            }
        }
        var result = StudyPlan(blocks: [], unscheduled: [], alreadyPlannedMinutes: 0)
        let ordered = tasks.filter(\.selected).sorted {
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
        for task in ordered {
            let credited = busy.filter { $0.taskID == task.id && $0.start >= now && $0.end <= task.deadline }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
            result.alreadyPlannedMinutes += min(task.minutes, credited)
            var remaining = max(0, Int(ceil(Double(task.minutes - credited) / 5)) * 5)
            for offset in 0..<p.days where remaining > 0 {
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                guard p.weekdays.contains(calendar.component(.weekday, from: day)), day < task.deadline else { continue }
                let start = calendar.date(bySettingHour: p.startMinute / 60, minute: p.startMinute % 60, second: 0, of: day)!
                let finish = p.endMinute == 1440 ? calendar.date(byAdding: .day, value: 1, to: day)! : calendar.date(bySettingHour: p.endMinute / 60, minute: p.endMinute % 60, second: 0, of: day)!
                let limit = min(finish, task.deadline)
                var cursor = roundedUp(max(start, now))
                while remaining > 0 && cursor < limit && usedByDay[day, default: 0] < p.dailyMinutes {
                    if let collision = occupied.filter({ $0.start <= cursor && $0.end > cursor }).max(by: { $0.end < $1.end }) {
                        cursor = roundedUp(collision.end); continue
                    }
                    let nextBusy = occupied.filter { $0.start > cursor }.map(\.start).min() ?? limit
                    let available = max(0, Int(min(limit, nextBusy).timeIntervalSince(cursor) / 60))
                    let duration = min(remaining, p.sessionMinutes, p.dailyMinutes - usedByDay[day, default: 0], available) / 5 * 5
                    guard duration >= min(15, remaining) else { cursor = roundedUp(min(limit, nextBusy).addingTimeInterval(60)); continue }
                    let block = PlannedStudyBlock(taskID: task.id, title: task.title, start: cursor, minutes: duration, steps: task.steps)
                    result.blocks.append(block)
                    let breakEnd = block.end.addingTimeInterval(Double(p.breakMinutes * 60))
                    occupied.append(PlanningBusyTime(start: block.start, end: breakEnd, taskID: task.id))
                    remaining -= duration; usedByDay[day, default: 0] += duration; cursor = roundedUp(breakEnd)
                }
            }
            if remaining > 0 {
                result.unscheduled.append(UnscheduledStudyWork(id: task.id, title: task.title, minutes: remaining,
                    reason: task.deadline <= now ? "Deadline has passed. Update it before planning." : "Not enough free study time before the deadline within this planning window."))
            }
        }
        result.blocks.sort { $0.start < $1.start }
        return result
    }
    private static func roundedUp(_ date: Date) -> Date { Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 300) * 300) }
}

public struct AIStudySuggestion: Codable, Equatable, Sendable {
    public let minutes: Int
    public let steps: [String]
    public static func decode(_ text: String) throws -> Self {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let data = clean.data(using: .utf8), data.count <= 10_000,
              let value = try? JSONDecoder().decode(Self.self, from: data), (15...2400).contains(value.minutes),
              (1...6).contains(value.steps.count), value.steps.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 240 })
        else { throw PlanningError.invalid("The AI response was not a valid study estimate. Your existing estimate is unchanged; you can enter it yourself or retry.") }
        return value
    }
}
