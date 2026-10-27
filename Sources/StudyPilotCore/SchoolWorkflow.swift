import Foundation

public enum SchoolAgenda {
    public static func occurs(start: Date, end: Date, on day: Date, calendar: Calendar = .current) -> Bool {
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, end >= start,
              let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return false }
        let first = calendar.startOfDay(for: day)
        return start == end ? start >= first && start < next : start < next && end > first
    }
}

public struct StudyRoutine: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var preferences: PlanningPreferences
    public init(id: UUID = UUID(), name: String, preferences: PlanningPreferences) {
        self.id = id; self.name = name; self.preferences = preferences
    }
}
public enum StudyRoutines {
    public static func saving(name: String, preferences: PlanningPreferences, in routines: [StudyRoutine]) throws -> [StudyRoutine] {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 40 else { throw PlanningError.invalid("Name your routine using 1–40 characters.") }
        try preferences.validate()
        var result = routines
        if let index = result.firstIndex(where: { $0.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            result[index].name = cleaned; result[index].preferences = preferences
        } else {
            guard result.count < 5 else { throw PlanningError.invalid("You can save five routines. Remove one or use an existing name to update it.") }
            result.append(StudyRoutine(name: cleaned, preferences: preferences))
        }
        return result
    }
}
public enum AssignmentChecklist {
    public static func setting(_ record: AssignmentRecord, itemID: UUID, completed: Bool) throws -> AssignmentRecord {
        var result = record
        guard let index = result.checklist.firstIndex(where: { $0.id == itemID }) else { throw PlanningError.invalid("This checklist item changed. Reopen the assignment to refresh it.") }
        result.checklist[index].isComplete = completed
        return result
    }
}
