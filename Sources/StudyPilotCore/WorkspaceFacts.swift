import Foundation

public struct StudyChatSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var kind: String
    public var localID: UUID?
    public var date: Date?
    public init(id: String, title: String, detail: String, kind: String, localID: UUID? = nil, date: Date? = nil) {
        self.id = id; self.title = String(title.prefix(500)); self.detail = String(detail.prefix(2000)); self.kind = kind; self.localID = localID; self.date = date
    }
}
public struct WorkspaceFactTask: Sendable {
    public let record: AssignmentRecord
    public let subject: String
    public let calendarSource: StudyChatSource?
    public var id: String { calendarSource?.id ?? record.id.uuidString }
    public init(record: AssignmentRecord, subject: String, calendarSource: StudyChatSource? = nil) { self.record = record; self.subject = subject; self.calendarSource = calendarSource }
}
public struct WorkspaceFactAnswer: Sendable {
    public let text: String
    public let sources: [StudyChatSource]
    public init(text: String, sources: [StudyChatSource]) { self.text = text; self.sources = sources }
}
public enum WorkspaceFactRequest: Equatable, Sendable {
    case tasksToday, tasksTomorrow, overdue, nextDeadline, tasks(String), calendar(Int)
    public var scope: String {
        switch self { case .tasksToday: "today"; case .tasksTomorrow: "tomorrow"; case .overdue: "overdue"; case .nextDeadline: "next"; case .tasks: "tasks"; case .calendar(let day): "calendar:\(day)" }
    }
}
public enum WorkspaceFacts {
    /// Conservative routing: tutoring, hypothetical questions, and mutations stay with the assistant.
    public static func request(_ text: String, followingWorkspaceAnswer: Bool = false, previousScope: String? = nil) -> WorkspaceFactRequest? {
        let words = Set(StudyUnderstanding.tokens(text)), normalized = StudyUnderstanding.tokens(text).joined(separator: " ")
        guard !StudyUnderstanding.requestsMove(messages: [.init(role: "user", text: text)]) else { return nil }
        if normalized.hasPrefix("what is a ") && !followingWorkspaceAnswer { return nil }
        if !words.isDisjoint(with: ["week", "weeks", "days", "yesterday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]) { return nil }
        if !words.isDisjoint(with: ["am", "pm"]) || ((!words.isDisjoint(with: ["at", "before", "after"])) && words.contains(where: { Int($0) != nil })) { return nil }
        if !words.isDisjoint(with: ["completed", "finished", "done"]) { return nil }
        if normalized.contains("when can") || normalized.contains("when should") || normalized.hasPrefix("help ") || normalized.hasPrefix("plan ") { return nil }
        let explain = !words.isDisjoint(with: ["explain", "teach", "solve", "why", "hypothetical", "imagine"])
        guard !explain else { return nil }
        if followingWorkspaceAnswer, (!StudyUnderstanding.topics(in: text).isEmpty || !words.isDisjoint(with: ["it", "that", "this", "one"])), words.isDisjoint(with: ["today", "tomorrow", "overdue", "next"]) {
            switch previousScope { case "today": return .tasksToday; case "tomorrow": return .tasksTomorrow; case "overdue": return .overdue; case "next": return .nextDeadline; case "calendar:0": return .calendar(0); case "calendar:1": return .calendar(1); default: break }
        }
        if !words.isDisjoint(with: ["calendar", "schedule", "agenda"]) && !words.isDisjoint(with: ["today", "tomorrow"]) {
            return .calendar(words.contains("tomorrow") ? 1 : 0)
        }
        let taskQuestion = !words.isDisjoint(with: ["task", "tasks", "assignment", "assignments", "homework", "deadline", "deadlines", "due", "overdue"]) || (followingWorkspaceAnswer && !StudyUnderstanding.topics(in: text).isEmpty)
        let personal = !words.isDisjoint(with: ["my", "our", "i", "have", "due", "overdue", "deadline", "deadlines", "list", "show", "find"]) || followingWorkspaceAnswer || !StudyUnderstanding.topics(in: text).isEmpty
        guard taskQuestion && personal else { return nil }
        if words.contains("overdue") || normalized.contains("past due") { return .overdue }
        if words.contains("next") && !words.isDisjoint(with: ["deadline", "due"]) { return .nextDeadline }
        if words.contains("tomorrow") { return .tasksTomorrow }
        if words.contains("today") { return .tasksToday }
        if !words.isDisjoint(with: ["list", "show", "find", "which", "what", "when", "have", "about"]) || normalized.hasSuffix("tasks") || normalized.hasSuffix("task") { return .tasks(text) }
        return nil
    }
    private static let generic = Set(StudyUnderstanding.tokens("what which when is are the my our i have do does due deadline deadlines task tasks assignment assignments homework show list find about a an on in for to today tomorrow overdue next upcoming calendar schedule agenda event events s how many unfinished active please can could would you me tell need want right now all currently it that this one those them"))
    public static func followupQuery(_ text: String, sources: [StudyChatSource]) -> String? {
        let words = Set(StudyUnderstanding.tokens(text))
        guard !words.isDisjoint(with: ["it", "that", "this", "one"]), StudyUnderstanding.topics(in: text).isEmpty else { return text }
        let titles = Set(sources.map { $0.title })
        if titles.count > 1 { return nil }
        return titles.first.map { text + " " + $0 } ?? text
    }
    public static func isSpecific(_ query: String) -> Bool { !StudyUnderstanding.tokens(query).allSatisfy { generic.contains($0) } }
    private static func matching(_ tasks: [WorkspaceFactTask], query: String) -> [WorkspaceFactTask] {
        guard isSpecific(query) else { return tasks }
        let items = tasks.map { StudyContextItem(id: $0.id, title: $0.record.title, subject: $0.subject, details: $0.record.details, due: $0.record.dueDate) }
        let broadSubjects = Set(["math", "maths", "mathematics", "science", "sciences", "english", "history", "geography", "japanese", "spanish", "french", "design", "pe"])
        let specific = StudyUnderstanding.tokens(query).filter { !generic.contains($0) && !broadSubjects.contains($0) }
        let direct = items.filter { item in specific.contains { term in StudyUnderstanding.tokens(item.title).contains { StudyUnderstanding.similar(term, $0) } } }
        let ids = Set((direct.isEmpty ? StudyUnderstanding.ranked(items, query: query) : direct).map(\.id))
        return tasks.filter { ids.contains($0.id) }
    }
    public static func taskAnswer(_ request: WorkspaceFactRequest, tasks: [WorkspaceFactTask], now: Date, calendar: Calendar = .current, query: String = "") -> WorkspaceFactAnswer? {
        let search: String
        if !query.isEmpty { search = query } else if case .tasks(let value) = request { search = value } else { search = "" }
        let active = matching(tasks.filter { $0.record.status != TaskStatus.done.rawValue }, query: search)
        let today = calendar.startOfDay(for: now), tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!, after = calendar.date(byAdding: .day, value: 2, to: today)!
        let chosen: [WorkspaceFactTask], label: String
        switch request {
        case .tasksToday: chosen = active.filter { $0.record.dueDate >= today && $0.record.dueDate < tomorrow }; label = "due today"
        case .tasksTomorrow: chosen = active.filter { $0.record.dueDate >= tomorrow && $0.record.dueDate < after }; label = "due tomorrow"
        case .overdue: chosen = active.filter { $0.record.dueDate < now }; label = "overdue"
        case .nextDeadline:
            chosen = Array(active.filter { $0.record.dueDate >= now }.sorted { $0.record.dueDate < $1.record.dueDate }.prefix(1)); label = "with the next upcoming deadline"
        case .tasks: chosen = active; label = "matching your request"
        case .calendar: return nil
        }
        let qualifier = isSpecific(search) && request.scope != "tasks" ? "matching your question and " : ""
        let sorted = chosen.sorted { $0.record.dueDate == $1.record.dueDate ? $0.id < $1.id : $0.record.dueDate < $1.record.dueDate }
        let mixed = sorted.contains { $0.calendarSource != nil }
        guard !sorted.isEmpty else { return .init(text: "No matching unfinished StudyPilot assignments or selected calendar deadlines \(qualifier)\(label) were found. Open Calendar to review raw events and the selected calendar sources.", sources: []) }
        let sources = sorted.prefix(10).map { item in
            item.calendarSource ?? StudyChatSource(id: "assignment:\(item.record.id)", title: item.record.title, detail: "Due \(item.record.dueDate.formatted(date: .abbreviated, time: .shortened)) · \(item.subject.isEmpty ? "No subject assigned" : item.subject) · \(item.record.status)", kind: "assignment", localID: item.record.id, date: item.record.dueDate)
        }
        let lines = sources.map { "• \($0.title) — \($0.detail)" }.joined(separator: "\n")
        return .init(text: "\(sorted.count) \(mixed ? "assignment/deadline items" : "unfinished StudyPilot assignment" + (sorted.count == 1 ? "" : "s")) \(qualifier)\(label):\n\n" + lines + (sorted.count > 10 ? "\n\nShowing the first 10. Open Assignments for the full list." : "") + "\n\nThese are deadlines, not scheduled study sessions." + (mixed ? " Completion is not tracked for external calendar deadlines; completed local assignments are excluded." : ""), sources: sources)
    }
}

public enum AssignmentTimeFilter: String, CaseIterable, Sendable {
    case any = "Any time", overdue = "Overdue", today = "Today", tomorrow = "Tomorrow", week = "Next 7 days"
    public func includes(_ item: AssignmentRecord, now: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: now)
        switch self {
        case .any: return true
        case .overdue: return item.status != TaskStatus.done.rawValue && item.dueDate < now
        case .today: return item.dueDate >= start && item.dueDate < calendar.date(byAdding: .day, value: 1, to: start)!
        case .tomorrow:
            let day = calendar.date(byAdding: .day, value: 1, to: start)!
            return item.dueDate >= day && item.dueDate < calendar.date(byAdding: .day, value: 1, to: day)!
        case .week: return item.dueDate >= start && item.dueDate < calendar.date(byAdding: .day, value: 7, to: start)!
        }
    }
}
public struct StudyWorkloadDay: Identifiable, Sendable {
    public let date: Date
    public let minutes: Int
    public let count: Int
    public var id: Date { date }
}
public enum TodayWorkspace {
    public static func workload(assignments: [AssignmentRecord], now: Date, calendar: Calendar = .current) -> [StudyWorkloadDay] {
        (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let tasks = assignments.filter { $0.status != TaskStatus.done.rawValue && $0.dueDate >= day && $0.dueDate < next }
            return StudyWorkloadDay(date: day, minutes: tasks.reduce(0) { $0 + max(0, $1.estimatedMinutes) }, count: tasks.count)
        }
    }
    public static func defaultDeadline(now: Date, calendar: Calendar = .current) -> Date {
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
        return evening > now ? evening : calendar.date(byAdding: .day, value: 1, to: evening)!
    }
}
