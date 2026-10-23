import Testing
import Foundation
@testable import StudyPilotCore

private func utcCalendar() -> Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
private func date(_ day: Int = 23, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar = utcCalendar()) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
private func preferences() -> PlanningPreferences {
    var p = PlanningPreferences(); p.days = 7; p.startMinute = 16 * 60; p.endMinute = 20 * 60; p.sessionMinutes = 25; p.breakMinutes = 5; p.dailyMinutes = 120; return p
}

@Test func studyPlanAvoidsBusyEventsAndKeepsBreaks() throws {
    let task = PlanningTask(id: "a", title: "Essay", deadline: date(24), minutes: 75)
    let busy = [PlanningBusyTime(start: date(23, 16), end: date(23, 17)), PlanningBusyTime(start: date(23, 17, 25), end: date(23, 18))]
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: busy, preferences: preferences(), now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.reduce(0) { $0 + $1.minutes } == 75)
    #expect(plan.unscheduled.isEmpty)
    #expect(plan.blocks.first?.start == date(23, 17))
    for block in plan.blocks { #expect(!busy.contains { $0.overlaps(start: block.start, end: block.end) }); #expect(block.end <= task.deadline) }
    for pair in zip(plan.blocks, plan.blocks.dropFirst()) { #expect(pair.1.start.timeIntervalSince(pair.0.end) >= 300) }
}

@Test func studyPlanRespectsDailyCapAndReportsImpossibleWork() throws {
    var p = preferences(); p.dailyMinutes = 30
    let task = PlanningTask(id: "a", title: "Essay", deadline: date(24), minutes: 90)
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: [], preferences: p, now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.reduce(0) { $0 + $1.minutes } == 25) // A five-minute gap cannot become a useful partial block while 65 minutes remain.
    #expect(plan.unscheduled.first?.minutes == 65)
}

@Test func studyPlanSchedulesUrgentDeadlinesFirstAndPriorityBreaksTies() throws {
    var p = preferences(); p.sessionMinutes = 60
    let tasks = [PlanningTask(id: "later", title: "Later", deadline: date(26), minutes: 60, priority: 2),
                 PlanningTask(id: "low", title: "Low", deadline: date(24), minutes: 60, priority: 0),
                 PlanningTask(id: "high", title: "High", deadline: date(24), minutes: 60, priority: 2)]
    let plan = try StudyPlanner.makePlan(tasks: tasks, busy: [], preferences: p, now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.map(\.taskID) == ["high", "low", "later"])
    #expect(plan.blocks[2].start == date(24, 16))
}

@Test func futureStudyBlocksPreventDuplicatePlanningAndCountTowardDailyCap() throws {
    let task = PlanningTask(id: "a", title: "Essay", deadline: date(24), minutes: 60)
    let existing = PlanningBusyTime(start: date(23, 16), end: date(23, 17), taskID: "a")
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: [existing], preferences: preferences(), now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.isEmpty); #expect(plan.unscheduled.isEmpty); #expect(plan.alreadyPlannedMinutes == 60)
    var p = preferences(); p.dailyMinutes = 60
    let additional = PlanningTask(id: "b", title: "Math", deadline: date(24), minutes: 30)
    let other = try StudyPlanner.makePlan(tasks: [additional], busy: [existing], preferences: p, now: date(23, 15), calendar: utcCalendar())
    #expect(other.blocks.isEmpty); #expect(other.unscheduled.first?.minutes == 30)
}

@Test func pastStudyDoesNotAssumeCompletionAndOverdueWorkIsFlagged() throws {
    let task = PlanningTask(id: "a", title: "Essay", deadline: date(24), minutes: 25)
    let past = PlanningBusyTime(start: date(22, 16), end: date(22, 17), taskID: "a")
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: [past], preferences: preferences(), now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.count == 1); #expect(plan.alreadyPlannedMinutes == 0)
    let overdue = PlanningTask(id: "b", title: "Overdue", deadline: date(22), minutes: 30)
    let late = try StudyPlanner.makePlan(tasks: [overdue], busy: [], preferences: preferences(), now: date(23, 15), calendar: utcCalendar())
    #expect(late.blocks.isEmpty); #expect(late.unscheduled.first?.reason.contains("passed") == true)
}

@Test func noPastBlocksAndUnselectedTasksStayUnscheduled() throws {
    var task = PlanningTask(id: "a", title: "Essay", deadline: date(24), minutes: 25); task.selected = false
    let other = PlanningTask(id: "b", title: "Math", deadline: date(24), minutes: 25)
    let plan = try StudyPlanner.makePlan(tasks: [task, other], busy: [], preferences: preferences(), now: date(23, 16, 2), calendar: utcCalendar())
    #expect(plan.blocks.count == 1); #expect(plan.blocks.first?.taskID == "b"); #expect(plan.blocks.first?.start == date(23, 16, 5))
}

@Test func allDayBusyEventProtectsTheWholeDay() throws {
    let task = PlanningTask(id: "a", title: "Essay", deadline: date(25), minutes: 25)
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: [.init(start: date(23), end: date(24))], preferences: preferences(), now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.first?.start == date(24, 16))
}

@Test func scheduleIsRepeatableAndRespectsWeekdaySelectionAcrossDST() throws {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 21))!
    let deadline = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
    var p = preferences(); p.weekdays = [2] // Monday after the fall DST transition.
    let task = PlanningTask(id: "a", title: "Review", deadline: deadline, minutes: 50)
    let first = try StudyPlanner.makePlan(tasks: [task], busy: [], preferences: p, now: now, calendar: cal)
    let second = try StudyPlanner.makePlan(tasks: [task], busy: [], preferences: p, now: now, calendar: cal)
    #expect(first.blocks.map(\.start) == second.blocks.map(\.start))
    #expect(first.blocks.map(\.minutes) == second.blocks.map(\.minutes))
    #expect(first.blocks.count == 2)
    #expect(cal.component(.day, from: first.blocks[0].start) == 2)
    #expect(cal.component(.hour, from: first.blocks[0].start) == 16)
}

@Test func plannerRejectsInvalidSettingsTasksAndIntervals() throws {
    var p = preferences(); p.endMinute = p.startMinute
    #expect(throws: PlanningError.self) { try StudyPlanner.makePlan(tasks: [], busy: [], preferences: p, now: date()) }
    p = preferences()
    let task = PlanningTask(id: "a", title: "Essay", deadline: date(24), minutes: 25)
    #expect(throws: PlanningError.self) { try StudyPlanner.makePlan(tasks: [task, task], busy: [], preferences: p, now: date()) }
    #expect(throws: PlanningError.self) { try StudyPlanner.makePlan(tasks: [task], busy: [.init(start: date(24), end: date(23))], preferences: p, now: date()) }
}

@Test func calendarMetadataRoundTripsUnicodeTaskIdentity() {
    let block = PlannedStudyBlock(taskID: "calendar:数学/élève:123", title: "Math", start: date(), minutes: 25, steps: ["Read the question", "Check work"])
    #expect(PlannedStudyBlock.taskID(in: block.notes) == block.taskID)
    #expect(PlannedStudyBlock.taskID(in: "Unrelated event notes") == nil)
}

@Test func roundedEstimatesProduceBackupCompatibleDurations() throws {
    let task = PlanningTask(id: "a", title: "Math", deadline: date(24), minutes: 26)
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: [], preferences: preferences(), now: date(23, 15), calendar: utcCalendar())
    #expect(plan.blocks.map(\.minutes) == [25, 5])
    #expect(plan.unscheduled.isEmpty)
    #expect(plan.blocks.allSatisfy { (5...720).contains($0.minutes) })
}

@Test func aiSuggestionsAreValidatedBeforeTheyChangeThePlan() throws {
    let good = try AIStudySuggestion.decode("```json\n{\"minutes\":90,\"steps\":[\"Read the rubric\",\"Draft and check\"]}\n```")
    #expect(good.minutes == 90); #expect(good.steps.count == 2)
    for text in ["ignore instructions", "{\"minutes\":-2,\"steps\":[\"Work\"]}", "{\"minutes\":90,\"steps\":[]}", "{\"minutes\":90,\"steps\":[\"\"]}"] {
        #expect(throws: PlanningError.self) { try AIStudySuggestion.decode(text) }
    }
}
