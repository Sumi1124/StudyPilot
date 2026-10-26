import Foundation
import Testing
@testable import StudyPilotCore
private var factCalendar: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
private func factDate(_ day: Int, _ hour: Int = 0) -> Date { factCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
private func factTasks() -> [WorkspaceFactTask] {
    [.init(record: .init(title: "Quadratic equations", dueDate: factDate(26, 18), estimatedMinutes: 60), subject: "Mathematics"),
     .init(record: .init(title: "Trigonometry", dueDate: factDate(27, 10), estimatedMinutes: 30), subject: "Mathematics"),
     .init(record: .init(title: "Photosynthesis lab", dueDate: factDate(26, 16), estimatedMinutes: 45), subject: "Sciences"),
     .init(record: .init(title: "Essay", dueDate: factDate(25, 19), estimatedMinutes: 20), subject: "English"),
     .init(record: .init(title: "Already finished", dueDate: factDate(26, 18), status: TaskStatus.done.rawValue, estimatedMinutes: 100), subject: "Mathematics")]
}
@Test func factRoutingIsConservativeAndHonorsDateScopeFollowups() {
    #expect(WorkspaceFacts.request("What math tasks are due today?") == .tasksToday)
    #expect(WorkspaceFacts.request("What's on my calendar tomorrow?") == .calendar(1))
    #expect(WorkspaceFacts.request("What about science?", followingWorkspaceAnswer: true, previousScope: "today") == .tasksToday)
    #expect(WorkspaceFacts.request("Science tasks tomorrow", followingWorkspaceAnswer: true, previousScope: "today") == .tasksTomorrow)
    for text in ["Explain quadratic equations", "Move my math session tomorrow", "What is a deadline?", "What tasks are due this week?", "When can I do my math task?", "Show completed tasks"] { #expect(WorkspaceFacts.request(text) == nil) }
}
@Test func todaysFactsUseExactDayBoundariesAndExcludeCompletedAssignments() {
    let answer = WorkspaceFacts.taskAnswer(.tasksToday, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar)!
    #expect(Set(answer.sources.map(\.title)) == ["Quadratic equations", "Photosynthesis lab"])
    #expect(answer.sources.allSatisfy { $0.localID != nil && $0.date != nil })
    #expect(!answer.text.contains("Already finished"))
}
@Test func subjectAndTitleFactsDoNotListOtherSubjectsOrEveryMathTask() {
    let math = WorkspaceFacts.taskAnswer(.tasksToday, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar, query: "What math tasks are due today?")!
    #expect(math.sources.map(\.title) == ["Quadratic equations"])
    let exact = WorkspaceFacts.taskAnswer(.tasks("When is Quadratic equations due?"), tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar)!
    #expect(exact.sources.map(\.title) == ["Quadratic equations"])
}
@Test func nextDeadlineIsSelectedAfterSubjectFiltering() {
    let answer = WorkspaceFacts.taskAnswer(.nextDeadline, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar, query: "What is my next math deadline?")!
    #expect(answer.sources.first?.title == "Quadratic equations")
    let all = WorkspaceFacts.taskAnswer(.nextDeadline, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar)!
    #expect(all.sources.first?.title == "Photosynthesis lab")
}
@Test func tomorrowAndOverdueFactsUseRealDates() {
    #expect(WorkspaceFacts.taskAnswer(.tasksTomorrow, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar)?.sources.map(\.title) == ["Trigonometry"])
    #expect(WorkspaceFacts.taskAnswer(.overdue, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar)?.sources.map(\.title) == ["Essay"])
}
@Test func calendarDeadlineSourcesKeepUnknownCompletionExplicit() {
    let source = StudyChatSource(id: "calendar:sample", title: "Quadratic test", detail: "Calendar deadline; completion not tracked", kind: "calendar", date: factDate(26, 15))
    let item = WorkspaceFactTask(record: .init(title: source.title, dueDate: factDate(26, 15)), subject: "Mathematics", calendarSource: source)
    let answer = WorkspaceFacts.taskAnswer(.tasksToday, tasks: [item], now: factDate(26, 12), calendar: factCalendar)!
    #expect(answer.sources == [source]); #expect(answer.text.contains("Completion is not tracked"))
}
@Test func factualReferencesResolveOneItemButDoNotGuessBetweenSeveral() {
    let one = StudyChatSource(id: "a", title: "Quadratic equations", detail: "Math", kind: "assignment")
    let two = StudyChatSource(id: "b", title: "Trigonometry", detail: "Math", kind: "assignment")
    #expect(WorkspaceFacts.followupQuery("When is it due?", sources: [one])?.contains("Quadratic equations") == true)
    #expect(WorkspaceFacts.followupQuery("When is it due?", sources: [one, two]) == nil)
    #expect(WorkspaceFacts.followupQuery("What about science?", sources: [one]) == "What about science?")
}
@Test func timeFiltersAndWorkloadExcludeWrongDaysAndCompletedEffort() {
    let records = factTasks().map(\.record), now = factDate(26, 12)
    #expect(records.filter { AssignmentTimeFilter.overdue.includes($0, now: now, calendar: factCalendar) }.map(\.title) == ["Essay"])
    #expect(records.filter { AssignmentTimeFilter.tomorrow.includes($0, now: now, calendar: factCalendar) }.map(\.title) == ["Trigonometry"])
    let days = TodayWorkspace.workload(assignments: records, now: now, calendar: factCalendar)
    #expect(days.count == 7); #expect(days[0].minutes == 105); #expect(days[0].count == 2); #expect(days[1].minutes == 30)
    #expect(days.reduce(0) { $0 + $1.minutes } == 135)
    #expect(TodayWorkspace.defaultDeadline(now: factDate(26, 19), calendar: factCalendar) == factDate(27, 18))
}
@Test func factDayBoundaryRespectsDSTRatherThanAddingTwentyFourHours() {
    var cal = factCalendar; cal.timeZone = TimeZone(identifier: "America/New_York")!
    let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30))!
    let task = WorkspaceFactTask(record: .init(title: "Late task", dueDate: late), subject: "Math")
    #expect(WorkspaceFacts.taskAnswer(.tasksToday, tasks: [task], now: now, calendar: cal)?.sources.count == 1)
}
@Test func oldChatHistoryStillOpensAndNewSourceMetadataRoundTrips() throws {
    var thread = StudyChatThread(); thread.messages = [.init(role: "user", text: "Hello")]
    let encoder = JSONEncoder(), data = try encoder.encode([thread])
    var json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    var messages = json[0]["messages"] as! [[String: Any]]; messages[0].removeValue(forKey: "sources"); messages[0].removeValue(forKey: "answerKind"); messages[0].removeValue(forKey: "factScope"); json[0]["messages"] = messages
    #expect(try StudyChat.decode(JSONSerialization.data(withJSONObject: json)).first?.messages.first?.sources == nil)
    thread.messages.append(.init(role: "assistant", text: "Due today", sources: [.init(id: "x", title: "Math", detail: "Due", kind: "assignment")], answerKind: "workspace", factScope: "today"))
    #expect(try StudyChat.decode(encoder.encode([thread])) == [thread])
}
@Test func resolvedFactReferencesFilterTheTaskRatherThanReturningEveryAssignment() {
    let source = StudyChatSource(id: "quad", title: "Quadratic equations", detail: "Math", kind: "assignment")
    let query = WorkspaceFacts.followupQuery("When is it due?", sources: [source])!
    let answer = WorkspaceFacts.taskAnswer(.tasks("When is it due?"), tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar, query: query)!
    #expect(answer.sources.map(\.title) == ["Quadratic equations"])
}
@Test func tutoringQuestionsDoNotGetHijackedByCalendarOrUnrelatedTaskContext() {
    #expect(StudyUnderstanding.isLearningQuestion("Factor x^2 - 5x + 6 and verify by expanding."))
    #expect(!StudyUnderstanding.needsSavedStudyContext("Factor x^2 - 5x + 6 and verify by expanding."))
    #expect(StudyUnderstanding.isLearningQuestion("Explain my quadratic assignment"))
    #expect(StudyUnderstanding.needsSavedStudyContext("Explain my quadratic assignment"))
    #expect(!StudyUnderstanding.isLearningQuestion("Move my math session to tomorrow"))
    #expect(!StudyUnderstanding.isLearningQuestion("What tasks are due today?"))
}
@Test func unrecognizedCalendarQualifiersAreNotMisreportedAsExactEmptyResults() {
    #expect(WorkspaceFacts.request("Is there anything on my calendar today?") == nil)
    #expect(WorkspaceFacts.request("Show urgent tasks") == nil)
    #expect(WorkspaceFacts.request("What's on my calendar today?") == .calendar(0))
}
@Test func anUnanchoredPronounDoesNotBecomeAnExactAnswerAboutEveryTask() {
    #expect(WorkspaceFacts.followupQuery("When is it due?", sources: []) == nil)
}
