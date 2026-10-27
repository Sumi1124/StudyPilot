import Foundation
import Testing
@testable import StudyPilotCore

@Test func savedRoutinesReuseIdentityAndRespectLimits() throws {
    var preferences = PlanningPreferences()
    let saved = try StudyRoutines.saving(name: "  School week  ", preferences: preferences, in: [])
    #expect(saved.first?.name == "School week")
    preferences.dailyMinutes = 180; preferences.weekdays = [2,3,4,5,6]
    let changed = try StudyRoutines.saving(name: "SCHOOL WEEK", preferences: preferences, in: saved)
    #expect(changed.count == 1 && changed[0].id == saved[0].id)
    #expect(changed[0].preferences.dailyMinutes == 180 && changed[0].preferences.weekdays == [2,3,4,5,6])
    #expect(try JSONDecoder().decode([StudyRoutine].self, from: JSONEncoder().encode(changed)) == changed)
    var five = changed
    for name in ["Weekend", "Exams", "Holiday", "Evening"] { five = try StudyRoutines.saving(name: name, preferences: preferences, in: five) }
    #expect(throws: PlanningError.self) { _ = try StudyRoutines.saving(name: "Sixth", preferences: preferences, in: five) }
    #expect(try StudyRoutines.saving(name: "Weekend", preferences: preferences, in: five).count == 5)
    #expect(throws: PlanningError.self) { _ = try StudyRoutines.saving(name: "  ", preferences: preferences, in: []) }
    #expect(throws: PlanningError.self) { _ = try StudyRoutines.saving(name: String(repeating: "x", count: 41), preferences: preferences, in: []) }
    preferences.weekdays = []
    #expect(throws: PlanningError.self) { _ = try StudyRoutines.saving(name: "Invalid", preferences: preferences, in: []) }
}
@Test func inlineChecklistChangesOnlyTheRequestedItemWithoutFinishingTheTask() throws {
    let first = ChecklistItem(title: "Read"), second = ChecklistItem(title: "Practice")
    let original = AssignmentRecord(title: "Quadratics", dueDate: Date(timeIntervalSince1970: 10000), checklist: [first,second])
    let checked = try AssignmentChecklist.setting(original, itemID: first.id, completed: true)
    #expect(checked.checklist[0].isComplete && !checked.checklist[1].isComplete)
    #expect(checked.status == original.status && checked.completedAt == nil && checked.dueDate == original.dueDate)
    #expect(try AssignmentChecklist.setting(checked, itemID: first.id, completed: false) == original)
    #expect(throws: PlanningError.self) { _ = try AssignmentChecklist.setting(original, itemID: UUID(), completed: true) }
}
@Test func agendaUsesHalfOpenDaysForDeadlinesAndOvernightEvents() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 86400 * 100), next = day.addingTimeInterval(86400)
    #expect(SchoolAgenda.occurs(start: day, end: day, on: day, calendar: cal))
    #expect(!SchoolAgenda.occurs(start: next, end: next, on: day, calendar: cal))
    #expect(!SchoolAgenda.occurs(start: day.addingTimeInterval(-3600), end: day, on: day, calendar: cal))
    #expect(SchoolAgenda.occurs(start: next.addingTimeInterval(-1800), end: next.addingTimeInterval(1800), on: day, calendar: cal))
    #expect(SchoolAgenda.occurs(start: next.addingTimeInterval(-1800), end: next.addingTimeInterval(1800), on: next, calendar: cal))
    #expect(!SchoolAgenda.occurs(start: next, end: day, on: day, calendar: cal))
}
@Test func agendaUsesCalendarDayLengthAcrossDST() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
    let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 8))!
    let next = cal.date(byAdding: .day, value: 1, to: day)!
    #expect(next.timeIntervalSince(day) == 23 * 3600)
    #expect(SchoolAgenda.occurs(start: next.addingTimeInterval(-1), end: next, on: day, calendar: cal))
    #expect(!SchoolAgenda.occurs(start: next, end: next, on: day, calendar: cal))
}
