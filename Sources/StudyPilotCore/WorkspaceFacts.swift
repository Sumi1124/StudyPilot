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
    /// The next seven days, one weekday (Calendar weekday 1...7), a grouped overview, a ranked starting point, and workload totals.
    case tasksThisWeek, tasksOnWeekday(Int), overview, nextUp, workload
    public var scope: String {
        switch self {
        case .tasksToday: "today"; case .tasksTomorrow: "tomorrow"; case .overdue: "overdue"; case .nextDeadline: "next"; case .tasks: "tasks"; case .calendar(let day): "calendar:\(day)"
        case .tasksThisWeek: "week"; case .tasksOnWeekday(let day): "weekday:\(day)"; case .overview: "overview"; case .nextUp: "focus"; case .workload: "workload"
        }
    }
    /// Restores the scope saved with an earlier answer so a follow-up keeps it. Free-text task searches are not restored.
    public init?(scope: String) {
        switch scope {
        case "today": self = .tasksToday; case "tomorrow": self = .tasksTomorrow; case "overdue": self = .overdue; case "next": self = .nextDeadline
        case "calendar:0": self = .calendar(0); case "calendar:1": self = .calendar(1)
        case "week": self = .tasksThisWeek; case "overview": self = .overview; case "focus": self = .nextUp; case "workload": self = .workload
        default:
            guard scope.hasPrefix("weekday:"), let day = Int(scope.dropFirst("weekday:".count)), (1...7).contains(day) else { return nil }
            self = .tasksOnWeekday(day)
        }
    }
}
public enum WorkspaceFacts {
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    public static func needsWorkspaceContext(_ text: String) -> Bool {
        let words = Set(StudyUnderstanding.tokens(text))
        return !words.isDisjoint(with: ["task", "tasks", "assignment", "assignments", "homework", "deadline", "deadlines", "calendar", "calender", "schedule", "agenda", "overdue", "due", "unfinished", "outstanding", "remaining", "workload"]) || asksRemainingWork(text) || request(text) != nil
    }
    private static func asksRemainingWork(_ text: String) -> Bool {
        let value = StudyUnderstanding.tokens(text).joined(separator: " ")
        return ["what do i need to do", "what should i do", "what is left", "what s left", "what do i have left", "what i need to do", "what needs to be done", "what do i need to get done", "what i need to get done", "what is needed to be done", "what do i have to do", "what should i work on", "what am i supposed to do", "what have i got to do"].contains { value.contains($0) }
    }
    /// “Where do I start?” questions. Callers still require a task word or an otherwise generic question.
    private static func asksPriority(_ text: String) -> Bool {
        let words = StudyUnderstanding.tokens(text), value = words.joined(separator: " ")
        return ["work on first", "do first", "start with", "should i start", "work on next", "do next", "focus on", "most urgent", "most important", "should i work on", "what should i do"].contains { value.contains($0) }
            || !Set(words).isDisjoint(with: ["urgent", "prioritize", "prioritise", "priority", "priorities"])
    }
    /// “How much is left?” questions about counts or estimated time.
    private static func asksWorkload(_ text: String) -> Bool {
        let words = StudyUnderstanding.tokens(text), value = words.joined(separator: " ")
        return value.contains("how much") || value.contains("how many") || value.contains("how long") || words.contains("workload")
    }
    /// Conservative routing: tutoring, hypothetical questions, and mutations stay with the assistant.
    public static func request(_ text: String, followingWorkspaceAnswer: Bool = false, previousScope: String? = nil) -> WorkspaceFactRequest? {
        let words = Set(StudyUnderstanding.tokens(text)), normalized = StudyUnderstanding.tokens(text).joined(separator: " ")
        guard !StudyUnderstanding.requestsMove(messages: [.init(role: "user", text: text)]) else { return nil }
        if isSpecific(text) && StudyUnderstanding.topics(in: text).isEmpty { return nil }
        if normalized.hasPrefix("what is a ") && !followingWorkspaceAnswer { return nil }
        let sevenDays = normalized.contains("next 7 days") || normalized.contains("next seven days")
        let wantsWeek = sevenDays || words.contains("week")
        let weekday = weekdayNames.firstIndex(where: { words.contains($0) }).map { $0 + 1 }
        let calendarWords = !words.isDisjoint(with: ["calendar", "calender", "schedule", "agenda"])
        if !words.isDisjoint(with: ["weeks", "yesterday"]) || (!sevenDays && !words.isDisjoint(with: ["days", "7", "seven"])) { return nil }
        // Only the coming seven days and one plain weekday are exact; other ranges stay with the assistant.
        if wantsWeek || weekday != nil {
            if calendarWords || (wantsWeek && weekday != nil) || weekdayNames.filter({ words.contains($0) }).count > 1 { return nil }
            if !words.isDisjoint(with: ["last", "every", "each"]) || (words.contains("next") && !sevenDays) { return nil }
        }
        if !words.isDisjoint(with: ["am", "pm", "at", "before", "after"]) && words.contains(where: { Int($0) != nil }) { return nil }
        if !words.isDisjoint(with: ["completed", "finished", "done"]) && !asksRemainingWork(text) { return nil }
        if normalized.contains("when can") || normalized.contains("when should") || normalized.hasPrefix("help ") || normalized.hasPrefix("plan ") { return nil }
        let explain = !words.isDisjoint(with: ["explain", "teach", "solve", "why", "hypothetical", "imagine"])
        guard !explain else { return nil }
        let taskWords = !words.isDisjoint(with: ["task", "tasks", "assignment", "assignments", "homework", "deadline", "deadlines"])
        let priority = asksPriority(text) && (taskWords || !isSpecific(text) || asksRemainingWork(text))
        let workload = asksWorkload(text) && (taskWords || !words.isDisjoint(with: ["work", "left", "remaining", "workload"]))
        let dated = !words.isDisjoint(with: ["today", "tonight", "tomorrow", "overdue", "next"]) || wantsWeek || weekday != nil
        if followingWorkspaceAnswer, (!StudyUnderstanding.topics(in: text).isEmpty || !words.isDisjoint(with: ["it", "that", "this", "one"])), !dated, !priority, !workload,
           let previous = previousScope.flatMap({ WorkspaceFactRequest(scope: $0) }) { return previous }
        // Loosely worded calendar questions stay with the assistant; only plain day requests are exact.
        if calendarWords && !words.isDisjoint(with: ["any", "anything", "there", "got", "soon", "supposed"]) { return nil }
        if calendarWords && !words.isDisjoint(with: ["today", "tonight", "tomorrow"]) {
            return .calendar(words.contains("tomorrow") ? 1 : 0)
        }
        let taskQuestion = asksRemainingWork(text) || priority || workload || !words.isDisjoint(with: ["task", "tasks", "assignment", "assignments", "homework", "deadline", "deadlines", "due", "overdue"]) || (followingWorkspaceAnswer && !StudyUnderstanding.topics(in: text).isEmpty)
        let personal = asksRemainingWork(text) || priority || workload || !words.isDisjoint(with: ["my", "our", "i", "have", "due", "overdue", "deadline", "deadlines", "list", "show", "find", "left", "remaining", "unfinished", "outstanding"]) || followingWorkspaceAnswer || !StudyUnderstanding.topics(in: text).isEmpty
        guard taskQuestion && personal else { return nil }
        if words.contains("overdue") || normalized.contains("past due") { return .overdue }
        if words.contains("next") && !sevenDays && !words.isDisjoint(with: ["deadline", "due"]) { return .nextDeadline }
        if wantsWeek { return .tasksThisWeek }
        if let weekday { return .tasksOnWeekday(weekday) }
        if words.contains("tomorrow") { return .tasksTomorrow }
        if words.contains("today") || words.contains("tonight") { return .tasksToday }
        if workload { return .workload }
        if priority { return .nextUp }
        if asksRemainingWork(text) || !words.isDisjoint(with: ["left", "remaining", "unfinished", "outstanding"]) { return .overview }
        if !words.isDisjoint(with: ["list", "show", "find", "which", "what", "when", "have", "about", "remind"]) || normalized.hasSuffix("tasks") || normalized.hasSuffix("task") { return .tasks(text) }
        return nil
    }
    private static let generic = Set(StudyUnderstanding.tokens("what which when is are the my our i have do does due deadline deadlines task tasks assignment assignments homework show list find about a an on in for to today tomorrow overdue next upcoming calendar calender schedule agenda event events s how many unfinished active of please can could would you me tell need want right now all currently it that this one those them left remaining still outstanding remind needed needs be get should done work urgent first start with prioritize prioritise priority priorities important focus most week seven 7 days much long time take will total workload sunday monday tuesday wednesday thursday friday saturday any anything there got soon tonight am supposed"))
    public static func followupQuery(_ text: String, sources: [StudyChatSource]) -> String? {
        let words = Set(StudyUnderstanding.tokens(text))
        guard !words.isDisjoint(with: ["it", "that", "this", "one"]), StudyUnderstanding.topics(in: text).isEmpty else { return text }
        // “Which one first?” and “how much is that?” refer to the whole list, not one unnamed item.
        if !isSpecific(text) && (asksPriority(text) || asksWorkload(text) || words.contains("week")) { return text }
        let titles = Set(sources.map { $0.title })
        if titles.count != 1 { return nil }
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
    /// Compact study time: “45 min”, “2 h”, “1 h 30 min”.
    public static func duration(_ minutes: Int) -> String {
        let value = max(0, minutes), hours = value / 60, rest = value % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
    /// Plain distance to a deadline using calendar days, so “tomorrow” survives daylight-saving changes.
    public static func relativeDue(_ due: Date, now: Date, calendar: Calendar = .current) -> String {
        let minutes = Int(abs(due.timeIntervalSince(now)) / 60)
        let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0)
        let near = minutes < 60 ? "\(max(1, minutes)) min" : "\(minutes / 60) h"
        if due < now { return days == 0 ? near + " overdue" : "\(days) day\(days == 1 ? "" : "s") overdue" }
        return days == 0 ? "in " + near : days == 1 ? (minutes < 360 ? "tomorrow, in " + near : "tomorrow") : "in \(days) days"
    }
    private enum DueGroup: Int, CaseIterable {
        case overdue, today, tomorrow, week, later
        var title: String {
            switch self { case .overdue: "Overdue"; case .today: "Due today"; case .tomorrow: "Due tomorrow"; case .week: "Next 7 days"; case .later: "Later" }
        }
        static func of(_ due: Date, now: Date, calendar: Calendar) -> DueGroup {
            let today = calendar.startOfDay(for: now)
            func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
            if due < now { return .overdue }
            return due < day(1) ? .today : due < day(2) ? .tomorrow : due < day(7) ? .week : .later
        }
    }
    /// Overdue work first, then the nearest deadline; high priority counts as a day sooner and low priority a day later.
    public static func startingOrder(_ tasks: [WorkspaceFactTask], now: Date) -> [WorkspaceFactTask] {
        func key(_ item: WorkspaceFactTask) -> (Int, Date) {
            (item.record.dueDate < now ? 0 : 1, item.record.dueDate.addingTimeInterval(Double(1 - min(2, max(0, item.record.priority))) * 86_400))
        }
        return tasks.sorted { a, b in
            let lhs = key(a), rhs = key(b)
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 == rhs.1 ? a.id < b.id : lhs.1 < rhs.1
        }
    }
    public static func taskAnswer(_ request: WorkspaceFactRequest, tasks: [WorkspaceFactTask], now: Date, calendar: Calendar = .current, query: String = "") -> WorkspaceFactAnswer? {
        if case .calendar = request { return nil }
        let search: String
        if !query.isEmpty { search = query } else if case .tasks(let value) = request { search = value } else { search = "" }
        let active = matching(tasks.filter { $0.record.status != TaskStatus.done.rawValue }, query: search)
            .sorted { $0.record.dueDate == $1.record.dueDate ? $0.id < $1.id : $0.record.dueDate < $1.record.dueDate }
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func relative(_ item: WorkspaceFactTask) -> String { relativeDue(item.record.dueDate, now: now, calendar: calendar) }
        func source(_ item: WorkspaceFactTask) -> StudyChatSource {
            if let calendarSource = item.calendarSource { return calendarSource }
            let record = item.record
            var parts = ["Due \(record.dueDate.formatted(date: .abbreviated, time: .shortened)) (\(relative(item)))", item.subject.isEmpty ? "No subject assigned" : item.subject, record.status]
            if record.estimatedMinutes > 0 { parts.append("~" + duration(record.estimatedMinutes)) }
            if !record.checklist.isEmpty { parts.append("\(record.checklist.filter(\.isComplete).count)/\(record.checklist.count) steps done") }
            if record.priority >= 2 { parts.append("high priority") }
            return StudyChatSource(id: "assignment:\(record.id)", title: record.title, detail: parts.joined(separator: " · "), kind: "assignment", localID: record.id, date: record.dueDate)
        }
        func line(_ source: StudyChatSource) -> String { "• \(source.title) — \(source.detail)" }
        func counted(_ items: [WorkspaceFactTask]) -> String {
            "\(items.count) " + (items.contains { $0.calendarSource != nil } ? "assignment/deadline item" : "unfinished StudyPilot assignment") + (items.count == 1 ? "" : "s")
        }
        func minutes(_ items: [WorkspaceFactTask]) -> Int { items.filter { $0.calendarSource == nil }.reduce(0) { $0 + max(0, $1.record.estimatedMinutes) } }
        func effort(_ items: [WorkspaceFactTask]) -> String { minutes(items) > 0 ? " · about \(duration(minutes(items))) of estimated work" : "" }
        func footer(_ items: [WorkspaceFactTask]) -> String {
            "\n\nThese are deadlines, not scheduled study sessions." + (items.contains { $0.calendarSource != nil } ? " Completion is not tracked for external calendar deadlines, which have no time estimate; completed local assignments are excluded." : "")
        }
        func reason(_ item: WorkspaceFactTask) -> String {
            if item.record.dueDate < now { return "it is " + relative(item) }
            return (item.calendarSource == nil && item.record.priority >= 2 ? "it is high priority and due " : "it is due ") + relative(item)
        }
        let filtered = isSpecific(search)
        func nothing(_ label: String, hint: Bool) -> WorkspaceFactAnswer {
            let scope = [filtered && request.scope != "tasks" ? "matching your question" : "", label].filter { !$0.isEmpty }.joined(separator: " and ")
            var text = "No unfinished StudyPilot assignments or selected calendar deadlines\(scope.isEmpty ? "" : " " + scope) were found."
            if hint {
                let overdue = active.filter { $0.record.dueDate < now }.count
                if overdue > 0 && request != .overdue { text += " \(overdue) overdue item\(overdue == 1 ? " still needs" : "s still need") attention." }
                if let next = active.first(where: { $0.record.dueDate >= now }) { text += " Next deadline: \(next.record.title) (\(relative(next)))." }
            }
            return .init(text: text + " Open Calendar to review raw events and the selected calendar sources.", sources: [])
        }
        let groups = DueGroup.allCases.map { group in (group, active.filter { DueGroup.of($0.record.dueDate, now: now, calendar: calendar) == group }) }.filter { !$0.1.isEmpty }
        let matchNote = filtered ? " matching your question" : ""
        switch request {
        case .overview:
            guard !active.isEmpty else { return nothing("", hint: false) }
            var sections: [String] = [], sources: [StudyChatSource] = []
            for (group, items) in groups where sources.count < 12 {
                let shown = items.prefix(12 - sources.count).map(source)
                sources += shown
                sections.append("\(group.title) (\(items.count)):\n" + shown.map(line).joined(separator: "\n"))
            }
            let first = startingOrder(active, now: now)[0]
            return .init(text: "\(counted(active)) left\(matchNote)\(effort(active)):\n\n" + sections.joined(separator: "\n\n")
                + (active.count > sources.count ? "\n\nShowing the first \(sources.count). Open Assignments for the full list." : "")
                + (active.count > 1 ? "\n\nSuggested start: \(first.record.title) — \(reason(first))." : "") + footer(active), sources: sources)
        case .nextUp:
            guard !active.isEmpty else { return nothing("", hint: false) }
            let top = Array(startingOrder(active, now: now).prefix(3)), first = top[0]
            var text = "Start with \(first.record.title) — \(reason(first))."
            if first.calendarSource == nil && first.record.estimatedMinutes > 0 { text += " It should take about \(duration(first.record.estimatedMinutes))." }
            if let step = first.record.checklist.first(where: { !$0.isComplete }) { text += " Next step: \(step.title)." }
            if top.count > 1 { text += "\n\nThen:\n" + top.enumerated().dropFirst().map { "\($0.offset + 1). \($0.element.record.title) — \(reason($0.element))" }.joined(separator: "\n") }
            text += "\n\nRanked by deadline and priority from \(counted(active))\(matchNote)." + (active.count > top.count ? " Ask “What’s left?” for the full list." : "")
            return .init(text: text + footer(top), sources: top.map(source))
        case .workload:
            guard !active.isEmpty else { return nothing("", hint: false) }
            let rows = groups.map { group, items in "• \(group.title): \(items.count)" + (minutes(items) > 0 ? " · \(duration(minutes(items)))" : "") }
            return .init(text: "\(counted(active)) left\(matchNote)\(effort(active)).\n\n" + rows.joined(separator: "\n")
                + "\n\nTime totals use each StudyPilot assignment’s saved estimate." + footer(active), sources: active.prefix(10).map(source))
        default: break
        }
        let chosen: [WorkspaceFactTask], label: String
        switch request {
        case .tasksToday: chosen = active.filter { $0.record.dueDate >= today && $0.record.dueDate < day(1) }; label = "due today"
        case .tasksTomorrow: chosen = active.filter { $0.record.dueDate >= day(1) && $0.record.dueDate < day(2) }; label = "due tomorrow"
        case .tasksThisWeek: chosen = active.filter { $0.record.dueDate >= today && $0.record.dueDate < day(7) }; label = "due in the next 7 days"
        case .tasksOnWeekday(let weekday):
            let offset = (weekday - calendar.component(.weekday, from: today) + 7) % 7
            chosen = active.filter { $0.record.dueDate >= day(offset) && $0.record.dueDate < day(offset + 1) }
            label = "due on \(weekdayNames[(weekday + 6) % 7].capitalized) (\(day(offset).formatted(date: .abbreviated, time: .omitted)))"
        case .overdue: chosen = active.filter { $0.record.dueDate < now }; label = "overdue"
        case .nextDeadline: chosen = Array(active.filter { $0.record.dueDate >= now }.prefix(1)); label = "with the next upcoming deadline"
        default: chosen = active; label = "matching your request"
        }
        guard !chosen.isEmpty else { return nothing(label, hint: request.scope != "tasks") }
        let qualifier = filtered && request.scope != "tasks" ? "matching your question and " : ""
        let sources = chosen.prefix(10).map(source)
        var extra = ""
        let overdue = active.filter { $0.record.dueDate < now && !chosen.map(\.id).contains($0.id) }.count
        if overdue > 0, request != .overdue, request.scope != "tasks" { extra = "\n\n\(overdue) overdue item\(overdue == 1 ? " also needs" : "s also need") attention. Ask “Which tasks are overdue?” to see \(overdue == 1 ? "it" : "them")." }
        return .init(text: "\(counted(chosen)) \(qualifier)\(label)\(effort(chosen)):\n\n" + sources.map(line).joined(separator: "\n")
            + (chosen.count > 10 ? "\n\nShowing the first 10. Open Assignments for the full list." : "") + extra + footer(chosen), sources: sources)
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
