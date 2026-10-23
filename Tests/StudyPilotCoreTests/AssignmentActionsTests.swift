import Testing
import Foundation
@testable import StudyPilotCore

@Test func assignmentBulkActionsOnlyChangeVisibleSelectedTasks() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let visible = AssignmentRecord(title: "Visible", dueDate: now)
    let hidden = AssignmentRecord(title: "Hidden", dueDate: now)
    let unselected = AssignmentRecord(title: "Unselected", dueDate: now)
    let updates = AssignmentActions.updates(
        records: [visible, hidden, unselected], selectedIDs: [visible.id, hidden.id, UUID()],
        visibleIDs: [visible.id, unselected.id], action: .status(.done), now: now
    )
    #expect(updates.map(\.id) == [visible.id])
    #expect(updates.first?.completedAt == now)
    #expect(updates.first?.status == TaskStatus.done.rawValue)
}

@Test func assignmentBulkStatusPreservesCompletionHistoryAndChecklist() {
    let earlier = Date(timeIntervalSince1970: 1_700_000_000)
    let now = earlier.addingTimeInterval(3600)
    let complete = AssignmentRecord(title: "Finished", status: TaskStatus.done.rawValue,
                                    checklist: [ChecklistItem(title: "Read", isComplete: true)], completedAt: earlier)
    let repeatDone = AssignmentActions.updates(records: [complete], selectedIDs: [complete.id], visibleIDs: [complete.id], action: .status(.done), now: now)
    #expect(repeatDone.isEmpty)
    let reopened = AssignmentActions.updates(records: [complete], selectedIDs: [complete.id], visibleIDs: [complete.id], action: .status(.inProgress), now: now)
    #expect(reopened.first?.completedAt == nil)
    #expect(reopened.first?.status == TaskStatus.inProgress.rawValue)
    #expect(reopened.first?.checklist == complete.checklist)
}

@Test func assignmentBulkDateShiftPreservesWallTimeAndReminderAcrossDST() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 15, minute: 30))!
    let task = AssignmentRecord(title: "Essay", dueDate: due, reminderDate: due.addingTimeInterval(-7200))
    let forward = AssignmentActions.updates(records: [task], selectedIDs: [task.id], visibleIDs: [task.id], action: .shiftDays(1), now: due, calendar: calendar)[0]
    #expect(calendar.component(.day, from: forward.dueDate) == 8)
    #expect(calendar.component(.hour, from: forward.dueDate) == 15)
    #expect(calendar.component(.minute, from: forward.dueDate) == 30)
    #expect(forward.dueDate.timeIntervalSince(due) == 23 * 3600)
    #expect(forward.dueDate.timeIntervalSince(forward.reminderDate!) == 7200)
    let restored = AssignmentActions.updates(records: [forward], selectedIDs: [task.id], visibleIDs: [task.id], action: .shiftDays(-1), now: due, calendar: calendar)[0]
    #expect(restored == task)
}

@Test func assignmentBulkDateShiftDoesNotCreateReminderOrAlterTaskContents() {
    let due = Date(timeIntervalSince1970: 1_700_000_000)
    let task = AssignmentRecord(title: "Read", details: "Chapter 8", dueDate: due, estimatedMinutes: 50,
                                checklist: [ChecklistItem(title: "Take notes")])
    let result = AssignmentActions.updates(records: [task], selectedIDs: [task.id], visibleIDs: [task.id], action: .shiftDays(1), now: due)[0]
    #expect(result.reminderDate == nil)
    #expect(result.title == task.title)
    #expect(result.details == task.details)
    #expect(result.estimatedMinutes == task.estimatedMinutes)
    #expect(result.checklist == task.checklist)
}
