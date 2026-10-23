import Foundation

public enum AssignmentBulkAction: Sendable {
    case status(TaskStatus)
    case shiftDays(Int)
}

public enum AssignmentActions {
    /// Returns changed records only. Intersecting at execution time protects tasks hidden by a filter.
    public static func updates(
        records: [AssignmentRecord], selectedIDs: Set<UUID>, visibleIDs: Set<UUID>,
        action: AssignmentBulkAction, now: Date, calendar: Calendar = .current
    ) -> [AssignmentRecord] {
        let targets = selectedIDs.intersection(visibleIDs)
        return records.compactMap { original in
            guard targets.contains(original.id) else { return nil }
            var updated = original
            switch action {
            case .status(let status):
                updated.status = status.rawValue
                updated.completedAt = status == .done ? (original.completedAt ?? now) : nil
            case .shiftDays(let days):
                guard let day = calendar.date(byAdding: .day, value: days, to: original.dueDate) else { return nil }
                updated = PlannerLogic.reschedule(original, to: day, calendar: calendar)
            }
            return updated == original ? nil : updated
        }
    }
}
