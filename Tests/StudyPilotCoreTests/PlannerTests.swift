import Testing
import Foundation
@testable import StudyPilotCore

@Test func progressAndOverdue() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var task = AssignmentRecord(dueDate: now.addingTimeInterval(-1), checklist: [ChecklistItem(title: "Read", isComplete: true), ChecklistItem(title: "Write")])
    #expect(PlannerLogic.isOverdue(task, at: now))
    #expect(PlannerLogic.progress(task) == 0.5)
    task.status = TaskStatus.done.rawValue
    #expect(!PlannerLogic.isOverdue(task, at: now))
    #expect(PlannerLogic.progress(task) == 1)
}

@Test func reschedulingKeepsTimeAndReminderLead() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let due = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15, minute: 30))!
    let task = AssignmentRecord(dueDate: due, reminderDate: due.addingTimeInterval(-3600))
    let result = PlannerLogic.reschedule(task, to: due.addingTimeInterval(86_400 * 5), calendar: calendar)
    #expect(calendar.component(.hour, from: result.dueDate) == 15)
    #expect(result.dueDate.timeIntervalSince(result.reminderDate!) == 3600)
}
