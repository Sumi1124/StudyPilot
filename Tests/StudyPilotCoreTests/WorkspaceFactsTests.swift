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
    for text in ["Explain quadratic equations", "Move my math session tomorrow", "What is a deadline?", "What tasks are due next week?", "What was due last Friday?", "What is due in 3 days?", "When can I do my math task?", "Show completed tasks"] { #expect(WorkspaceFacts.request(text) == nil) }
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
    #expect(WorkspaceFacts.request("What's on my calendar this week?") == nil)
    #expect(WorkspaceFacts.request("What's on my calendar Friday?") == nil)
    #expect(WorkspaceFacts.request("What's on my calendar today?") == .calendar(0))
}
@Test func anUnanchoredPronounDoesNotBecomeAnExactAnswerAboutEveryTask() {
    #expect(WorkspaceFacts.followupQuery("When is it due?", sources: []) == nil)
}

@Test func remainingWorkQuestionsUseActualUnfinishedRecords() throws {
    for text in ["What task do I have left?", "What tasks do I have left?", "What do I need to do?", "What is needed to be done?", "Remind me what I need to get done", "Remind me of my tasks", "What homework is still outstanding?"] {
        let request = try #require(WorkspaceFacts.request(text))
        #expect(WorkspaceFacts.needsWorkspaceContext(text))
        let answer = try #require(WorkspaceFacts.taskAnswer(request, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar, query: text))
        #expect(answer.sources.count == 4)
        #expect(!answer.sources.contains { $0.title == "Already finished" })
    }
    #expect(WorkspaceFacts.request("What tasks do I have left today?") == .tasksToday)
    #expect(WorkspaceFacts.request("What is on my calender today?") == .calendar(0))
    for text in ["Show completed tasks", "Explain how to finish a task", "Move my math session tomorrow"] {
        #expect(WorkspaceFacts.request(text) == nil)
    }
    #expect(!WorkspaceFacts.needsWorkspaceContext("Explain quadratic equations"))
}

@Test func weekWeekdayPriorityAndWorkloadQuestionsRouteToExactAnswers() {
    #expect(WorkspaceFacts.request("What tasks are due this week?") == .tasksThisWeek)
    #expect(WorkspaceFacts.request("What homework is due in the next 7 days?") == .tasksThisWeek)
    #expect(WorkspaceFacts.request("What's due Friday?") == .tasksOnWeekday(6))
    #expect(WorkspaceFacts.request("Which math tasks are due on Monday?") == .tasksOnWeekday(2))
    for text in ["What should I work on first?", "What should I work on?", "Show urgent tasks", "Which assignment is most urgent?"] { #expect(WorkspaceFacts.request(text) == .nextUp) }
    for text in ["How much work do I have left?", "How many tasks do I have left?", "How long will my homework take?", "What is my workload?"] { #expect(WorkspaceFacts.request(text) == .workload) }
    for text in ["What tasks do I have left?", "What's left?", "What homework is still outstanding?"] { #expect(WorkspaceFacts.request(text) == .overview) }
    #expect(WorkspaceFacts.request("How many tasks are due today?") == .tasksToday)
    #expect(WorkspaceFacts.request("Which tasks are overdue this week?") == .overdue)
    // Tutoring and unrelated questions that merely share a phrase stay with the assistant.
    for text in ["What do I do next in this equation?", "How long is the essay?", "How much is 12 times 8?", "Why is this urgent?", "What should I do about my essay introduction?", "How many days until my deadline?"] { #expect(WorkspaceFacts.request(text) == nil) }
}
@Test func everyRequestScopeRoundTripsExceptFreeTextSearches() {
    let all: [WorkspaceFactRequest] = [.tasksToday, .tasksTomorrow, .overdue, .nextDeadline, .calendar(0), .calendar(1), .tasksThisWeek, .tasksOnWeekday(1), .tasksOnWeekday(7), .overview, .nextUp, .workload]
    for request in all { #expect(WorkspaceFactRequest(scope: request.scope) == request) }
    for scope in ["tasks", "weekday:0", "weekday:8", "weekday:x", "calendar:5", ""] { #expect(WorkspaceFactRequest(scope: scope) == nil) }
}
@Test func followupsKeepNewScopesButANewIntentReplacesThem() {
    #expect(WorkspaceFacts.request("What about science?", followingWorkspaceAnswer: true, previousScope: "overview") == .overview)
    #expect(WorkspaceFacts.request("What about math?", followingWorkspaceAnswer: true, previousScope: "week") == .tasksThisWeek)
    #expect(WorkspaceFacts.request("What about science?", followingWorkspaceAnswer: true, previousScope: "weekday:6") == .tasksOnWeekday(6))
    #expect(WorkspaceFacts.request("Which one should I do first?", followingWorkspaceAnswer: true, previousScope: "overview") == .nextUp)
    let sources = [StudyChatSource(id: "a", title: "Essay", detail: "", kind: "assignment"), StudyChatSource(id: "b", title: "Trigonometry", detail: "", kind: "assignment")]
    #expect(WorkspaceFacts.followupQuery("Which one should I do first?", sources: sources) == "Which one should I do first?")
    #expect(WorkspaceFacts.followupQuery("When is it due?", sources: sources) == nil)
}
@Test func overviewGroupsUnfinishedWorkByUrgencyWithTotals() throws {
    let answer = try #require(WorkspaceFacts.taskAnswer(.overview, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar))
    #expect(answer.sources.map(\.title) == ["Essay", "Photosynthesis lab", "Quadratic equations", "Trigonometry"])
    #expect(answer.text.hasPrefix("4 unfinished StudyPilot assignments left · about 2 h 35 min of estimated work:"))
    for heading in ["Overdue (1):", "Due today (2):", "Due tomorrow (1):"] { #expect(answer.text.contains(heading)) }
    #expect(!answer.text.contains("Next 7 days")); #expect(!answer.text.contains("Later"))
    let order = ["Overdue (1)", "Due today (2)", "Due tomorrow (1)", "Suggested start: Essay — it is 1 day overdue."].map { answer.text.range(of: $0)!.lowerBound }
    #expect(order == order.sorted())
    #expect(!answer.text.contains("Already finished"))
    let math = try #require(WorkspaceFacts.taskAnswer(.overview, tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar, query: "What math tasks do I have left?"))
    #expect(math.sources.map(\.title) == ["Quadratic equations", "Trigonometry"]); #expect(math.text.contains("matching your question"))
}
@Test func longOverviewsAreCappedAndSayHowManyAreShown() throws {
    let many = (0..<15).map { WorkspaceFactTask(record: .init(title: "Task \($0)", dueDate: factDate(27 + $0 % 3, 9), estimatedMinutes: 10), subject: "") }
    let answer = try #require(WorkspaceFacts.taskAnswer(.overview, tasks: many, now: factDate(26, 12), calendar: factCalendar))
    #expect(answer.sources.count == 12); #expect(answer.text.contains("15 unfinished StudyPilot assignments left")); #expect(answer.text.contains("Showing the first 12."))
}
@Test func startingPointPutsOverdueFirstThenWeighsPriorityAgainstDeadline() throws {
    var tasks = factTasks()
    let first = try #require(WorkspaceFacts.taskAnswer(.nextUp, tasks: tasks, now: factDate(26, 12), calendar: factCalendar))
    #expect(first.sources.map(\.title) == ["Essay", "Photosynthesis lab", "Quadratic equations"])
    #expect(first.text.hasPrefix("Start with Essay — it is 1 day overdue. It should take about 20 min."))
    #expect(first.text.contains("2. Photosynthesis lab — it is due in 4 h")); #expect(first.text.contains("from 4 unfinished StudyPilot assignments"))
    // A high-priority task due tomorrow outranks normal work due later today, but never overdue work.
    tasks[1] = .init(record: .init(title: "Trigonometry", dueDate: factDate(27, 10), priority: 2, estimatedMinutes: 30, checklist: [.init(title: "Read notes", isComplete: true), .init(title: "Practice set B")]), subject: "Mathematics")
    let ranked = WorkspaceFacts.startingOrder(tasks.filter { $0.record.status != TaskStatus.done.rawValue }, now: factDate(26, 12)).map(\.record.title)
    #expect(ranked == ["Essay", "Trigonometry", "Photosynthesis lab", "Quadratic equations"])
    let math = try #require(WorkspaceFacts.taskAnswer(.nextUp, tasks: tasks, now: factDate(26, 12), calendar: factCalendar, query: "Which math task should I do first?"))
    #expect(math.text.hasPrefix("Start with Trigonometry — it is high priority and due tomorrow. It should take about 30 min. Next step: Practice set B."))
    #expect(math.sources.first?.detail.contains("1/2 steps done") == true); #expect(math.sources.first?.detail.contains("high priority") == true)
    let low = WorkspaceFactTask(record: .init(title: "Low", dueDate: factDate(26, 11), priority: 0), subject: "")
    #expect(WorkspaceFacts.startingOrder([tasks[2], low], now: factDate(26, 12)).first?.record.title == "Low")
}
@Test func workloadTotalsCountLocalEstimatesOnlyAndExcludeCompletedWork() throws {
    let source = StudyChatSource(id: "calendar:quiz", title: "History quiz", detail: "Calendar deadline; completion not tracked", kind: "calendar", date: factDate(29, 9))
    let tasks = factTasks() + [WorkspaceFactTask(record: .init(title: "History quiz", dueDate: factDate(29, 9)), subject: "", calendarSource: source)]
    let answer = try #require(WorkspaceFacts.taskAnswer(.workload, tasks: tasks, now: factDate(26, 12), calendar: factCalendar))
    #expect(answer.text.hasPrefix("5 assignment/deadline items left · about 2 h 35 min of estimated work."))
    for row in ["• Overdue: 1 · 20 min", "• Due today: 2 · 1 h 45 min", "• Due tomorrow: 1 · 30 min", "• Next 7 days: 1\n"] { #expect(answer.text.contains(row)) }
    #expect(answer.text.contains("Completion is not tracked")); #expect(answer.sources.count == 5)
}
@Test func weekAndWeekdayListsUseHalfOpenCalendarDays() throws {
    // 26 October 2026 is a Monday.
    let later = WorkspaceFactTask(record: .init(title: "Next Monday", dueDate: factDate(2, 0).addingTimeInterval(31 * 86_400)), subject: "")
    let friday = WorkspaceFactTask(record: .init(title: "Friday report", dueDate: factDate(30, 15)), subject: "")
    let tasks = factTasks() + [later, friday], now = factDate(26, 12)
    let week = try #require(WorkspaceFacts.taskAnswer(.tasksThisWeek, tasks: tasks, now: now, calendar: factCalendar))
    #expect(week.sources.map(\.title) == ["Photosynthesis lab", "Quadratic equations", "Trigonometry", "Friday report"])
    #expect(week.text.contains("due in the next 7 days")); #expect(week.text.contains("1 overdue item also needs attention."))
    let onFriday = try #require(WorkspaceFacts.taskAnswer(.tasksOnWeekday(6), tasks: tasks, now: now, calendar: factCalendar))
    #expect(onFriday.sources.map(\.title) == ["Friday report"]); #expect(onFriday.text.contains("due on Friday"))
    // Asking for today's weekday means today, not a week from now.
    #expect(WorkspaceFacts.taskAnswer(.tasksOnWeekday(2), tasks: tasks, now: now, calendar: factCalendar)?.sources.map(\.title) == ["Photosynthesis lab", "Quadratic equations"])
    let empty = try #require(WorkspaceFacts.taskAnswer(.tasksOnWeekday(5), tasks: tasks, now: now, calendar: factCalendar))
    #expect(empty.sources.isEmpty); #expect(empty.text.contains("1 overdue item still needs attention.")); #expect(empty.text.contains("Next deadline: Photosynthesis lab (in 4 h)."))
}
@Test func emptyWorkspacesGetAPlainAnswerInsteadOfACrash() throws {
    for request in [WorkspaceFactRequest.overview, .nextUp, .workload, .tasksThisWeek, .tasksOnWeekday(3), .overdue] {
        let answer = try #require(WorkspaceFacts.taskAnswer(request, tasks: [factTasks()[4]], now: factDate(26, 12), calendar: factCalendar))
        #expect(answer.sources.isEmpty); #expect(answer.text.hasPrefix("No unfinished StudyPilot assignments or selected calendar deadlines"))
    }
    #expect(WorkspaceFacts.taskAnswer(.calendar(0), tasks: factTasks(), now: factDate(26, 12), calendar: factCalendar) == nil)
}
@Test func durationsAndRelativeDeadlinesReadNaturally() {
    #expect([0, 45, 60, 90, 155, -5].map(WorkspaceFacts.duration) == ["0 min", "45 min", "1 h", "1 h 30 min", "2 h 35 min", "0 min"])
    let now = factDate(26, 12)
    func relative(_ date: Date) -> String { WorkspaceFacts.relativeDue(date, now: now, calendar: factCalendar) }
    #expect(relative(now.addingTimeInterval(-20)) == "1 min overdue"); #expect(relative(factDate(26, 9)) == "3 h overdue")
    #expect(relative(factDate(25, 23)) == "1 day overdue"); #expect(relative(factDate(20, 12)) == "6 days overdue")
    #expect(relative(now.addingTimeInterval(30 * 60)) == "in 30 min"); #expect(relative(factDate(26, 18)) == "in 6 h")
    #expect(relative(factDate(27, 1)) == "tomorrow"); #expect(relative(factDate(29, 0)) == "in 3 days")
    var cal = factCalendar; cal.timeZone = TimeZone(identifier: "America/New_York")!
    let beforeChange = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23))!, after = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 30))!
    #expect(WorkspaceFacts.relativeDue(after, now: beforeChange, calendar: cal) == "in 2 days")
}
@Test func everydayFillerWordsStillGetDirectAnswers() {
    #expect(WorkspaceFacts.request("Is anything overdue?") == .overdue)
    #expect(WorkspaceFacts.request("Anything due tomorrow?") == .tasksTomorrow)
    #expect(WorkspaceFacts.request("Is there any homework due today?") == .tasksToday)
    #expect(WorkspaceFacts.request("What's due tonight?") == .tasksToday)
    #expect(WorkspaceFacts.request("What am I supposed to do today?") == .tasksToday)
    #expect(WorkspaceFacts.request("What have I got to do?") == .overview)
    #expect(WorkspaceFacts.request("What's on my calendar tonight?") == .calendar(0))
    // Clock times and tutoring still go to the assistant.
    #expect(WorkspaceFacts.request("What's due at 9 am tomorrow?") == nil)
    #expect(WorkspaceFacts.request("What is due before 5 pm?") == nil)
    #expect(WorkspaceFacts.request("Explain anything about photosynthesis") == nil)
    #expect(WorkspaceFacts.request("Is there any life on Mars?") == nil)
}
@Test func deadlinesJustAfterMidnightSayHowSoonTheyAre() {
    let lateEvening = factDate(26, 23)
    #expect(WorkspaceFacts.relativeDue(lateEvening.addingTimeInterval(90 * 60), now: lateEvening, calendar: factCalendar) == "tomorrow, in 1 h")
    #expect(WorkspaceFacts.relativeDue(lateEvening.addingTimeInterval(65 * 60), now: lateEvening, calendar: factCalendar) == "tomorrow, in 1 h")
    #expect(WorkspaceFacts.relativeDue(lateEvening.addingTimeInterval(51 * 60), now: lateEvening, calendar: factCalendar) == "in 51 min")
    #expect(WorkspaceFacts.relativeDue(factDate(27, 12), now: lateEvening, calendar: factCalendar) == "tomorrow")
}
