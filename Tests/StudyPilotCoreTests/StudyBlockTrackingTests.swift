import Testing
import Foundation
@testable import StudyPilotCore

private func instant(_ day: Int, _ hour: Int = 16, _ minute: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
@Test func blockCompletionAndMovementSurviveNotesAndBackup() throws {
    let block = PlannedStudyBlock(taskID: "calendar:数学", title: "Math", start: instant(23), minutes: 25, steps: ["Review"], deadline: instant(25))
    var progress = StudyBlockTracking.read(block.notes)
    #expect(progress.deadline == instant(25)); #expect(progress.completedAt == nil)
    progress.completedAt = instant(23, 17); progress.previousStart = block.start
    let notes = progress.writing(to: block.notes)
    #expect(StudyBlockTracking.read(notes) == progress)
    #expect(PlannedStudyBlock.taskID(in: notes) == block.taskID)
    #expect(notes.contains("1. Review"))
    #expect(progress.writing(to: notes) == notes)
    let event = PlannerEventRecord(title: "Study", details: notes)
    let restored = try JSONDecoder().decode(PlannerEventRecord.self, from: JSONEncoder().encode(event))
    #expect(StudyBlockTracking.read(restored.details).completedAt == progress.completedAt)
    progress.completedAt = nil
    #expect(StudyBlockTracking.read(progress.writing(to: notes)).completedAt == nil)
}
@Test func reschedulingMovesWholeBlockAroundConflictsAndKeepsDeadline() throws {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let prefs = PlanningPreferences()
    let busy = [PlanningBusyTime(start: instant(23, 16), end: instant(23, 17), taskID: "existing")]
    let start = try StudyBlockTracking.nextStart(minutes: 25, deadline: instant(24), busy: busy, preferences: prefs, now: instant(23, 16, 25), calendar: cal)
    #expect(start == instant(23, 17, 5))
    #expect(try StudyBlockTracking.nextStart(minutes: 25, deadline: instant(23, 16, 30), busy: busy, preferences: prefs, now: instant(23, 16, 25), calendar: cal) == nil)
    #expect(try StudyBlockTracking.nextStart(minutes: 25, deadline: instant(22), busy: [], preferences: prefs, now: instant(23), calendar: cal) == nil)
}
@Test func reschedulingHonorsCapsAndDoesNotSplitOrDuplicateExistingWork() throws {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    var prefs = PlanningPreferences(); prefs.dailyMinutes = 30
    let busy = [PlanningBusyTime(start: instant(23, 18), end: instant(23, 18, 25), taskID: "same-assignment")]
    let next = try StudyBlockTracking.nextStart(minutes: 25, deadline: instant(24), busy: busy, preferences: prefs, now: instant(23), calendar: cal)
    #expect(next == nil)
    #expect(StudyBlockTracking.read("Old or unrelated notes").completedAt == nil)
}
@Test func onlyEndedUncheckedBlocksAreAutomaticallyEligible() {
    let block = PlannedStudyBlock(taskID: "local:123", title: "Math", start: instant(23), minutes: 25)
    #expect(!StudyBlockTracking.isUnfinished(start: block.start, minutes: 25, notes: block.notes, now: instant(23, 16, 24)))
    #expect(StudyBlockTracking.isUnfinished(start: block.start, minutes: 25, notes: block.notes, now: instant(23, 16, 25)))
    let completed = StudyBlockTracking(completedAt: instant(23, 16, 20)).writing(to: block.notes)
    #expect(!StudyBlockTracking.isUnfinished(start: block.start, minutes: 25, notes: completed, now: instant(24)))
    #expect(!StudyBlockTracking.isUnfinished(start: block.start, minutes: 25, notes: "Regular class", now: instant(24)))
    // Moving the same event makes repeated checks idempotent until its new session ends.
    #expect(!StudyBlockTracking.isUnfinished(start: instant(24), minutes: 25, notes: block.notes, now: instant(23, 17)))
}
@Test func reschedulingSkipsPartialGapsForALaterWholeSlot() throws {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let busy = [PlanningBusyTime(start: instant(23, 16, 20), end: instant(23, 17))]
    let next = try StudyBlockTracking.nextStart(minutes: 25, deadline: instant(24), busy: busy, preferences: PlanningPreferences(), now: instant(23, 15), calendar: cal)
    #expect(next == instant(23, 17))
}
