import Foundation
import Observation
import SwiftData
import StudyPilotCore
import StudyPilotData

struct CalendarChatEntry {
    let value: CalendarChatEvent
    let local: PlannerEventRecord?
    let external: CalendarPlanningEvent?
    let busy: Bool
}
struct CalendarChatSnapshot {
    let summary: String
    let aliases: [String: CalendarChatEvent]
    let entries: [CalendarChatEntry]
}
struct CalendarChatProposal: Identifiable {
    let id = UUID()
    let threadID: UUID
    let entry: CalendarChatEntry
    let start: Date
    var end: Date { start.addingTimeInterval(entry.value.end.timeIntervalSince(entry.value.start)) }
}

@MainActor @Observable final class CalendarChatService {
    var enabled = true
    var studyBlocksOnly = false
    var from = Calendar.current.startOfDay(for: Date())
    var days = 7
    var visible: [CalendarChatEntry] = []
    var pending: CalendarChatProposal?
    var status: String?
    var error: String?
    private var context: ModelContext?
    private var planning: CalendarPlanningService?
    var connected: Bool { planning?.hasAccess == true }
    var range: DateInterval { DateInterval(start: Calendar.current.startOfDay(for: from), end: Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: from))!) }
    func configure(context: ModelContext, planning: CalendarPlanningService) { self.context = context; self.planning = planning }
    func connect() async { await planning?.connect(); if let error = planning?.error { self.error = error } else { refresh() } }
    func refresh() {
        do { visible = try entries(in: range); error = nil; status = "\(visible.count) events · \(connected ? "selected synced calendars + StudyPilot" : "StudyPilot only; connect calendars for Google") · refreshed \(Date().formatted(date: .omitted, time: .shortened))" }
        catch { self.error = error.localizedDescription }
    }
    func snapshot(query: String = "", maximumBytes: Int = 2400) throws -> CalendarChatSnapshot? {
        pending = nil
        guard enabled else { return nil }
        let current = try entries(in: range); visible = current
        let ranked = current.sorted { a, b in
            let left = StudyUnderstanding.score(query: query, title: a.value.title, subject: a.value.subject)
            let right = StudyUnderstanding.score(query: query, title: b.value.title, subject: b.value.subject)
            return left == right ? a.value.start < b.value.start : left > right
        }
        let (text, aliases) = try CalendarChat.summary(events: ranked.map(\.value), range: range, now: Date(), maximumBytes: maximumBytes)
        let source = connected ? "Calendars selected in Plan my study, synchronized by macOS. Changes may wait for Google sync." : "StudyPilot local calendar ONLY. Google/external calendars are not connected; do not claim to know external commitments."
        status = "\(current.count) events read for this message"
        return CalendarChatSnapshot(summary: source + "\n" + text, aliases: aliases, entries: current)
    }
    func studyContext(query: String, maximumBytes: Int = 1700) throws -> (String, Int) {
        let value = try studyBundle(query: query, maximumBytes: maximumBytes)
        return (value.text, value.sources.count)
    }
    func studyBundle(query: String, maximumBytes: Int = 1700) throws -> (text: String, sources: [StudyChatSource]) {
        guard let context else { throw PlanningError.invalid("Your study workspace is still opening.") }
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        let assignments = try context.fetch(FetchDescriptor<Assignment>()).filter { $0.status != TaskStatus.done.rawValue }
        let notes = try context.fetch(FetchDescriptor<Note>())
        var items = assignments.prefix(2000).map { item in
            StudyContextItem(id: "assignment:\(item.id)", title: item.title, subject: subjects.first { $0.id == item.subjectID }?.name ?? "", details: item.details, due: item.dueDate)
        }
        items += notes.prefix(2000).map { item in
            StudyContextItem(id: "note:\(item.id)", title: item.title, subject: subjects.first { $0.id == item.subjectID }?.name ?? "", kind: "Note title (attach the note to use its text)")
        }
        let evidence = try StudyUnderstanding.evidence(items: items, query: query, maximumBytes: maximumBytes)
        let sources = evidence.items.map { item in
            StudyChatSource(id: item.id, title: item.title, detail: item.subject.isEmpty ? "Related topic; saved item" : item.subject, kind: item.id.hasPrefix("note:") ? "note" : "assignment", localID: UUID(uuidString: String(item.id.split(separator: ":").last ?? "")), date: item.due)
        }
        return (evidence.text, sources)
    }
    func factAnswer(_ request: WorkspaceFactRequest, useStudyContext: Bool, query: String = "") throws -> WorkspaceFactAnswer {
        guard let context else { throw PlanningError.invalid("Your workspace is still opening.") }
        let now = Date()
        if case .calendar(let offset) = request {
            guard enabled else { return .init(text: "Enable Use my calendar in Context & sources so I can check that schedule.", sources: []) }
            let cal = Calendar.current, day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
            let range = DateInterval(start: day, end: cal.date(byAdding: .day, value: 1, to: day)!)
            let values = try entries(in: range).filter { !WorkspaceFacts.isSpecific(query) || StudyUnderstanding.score(query: query, title: $0.value.title, subject: $0.value.subject) > 0 }
            let label = offset == 0 ? "today" : "tomorrow"
            let scope = connected ? "StudyPilot and your selected synced calendars" : "StudyPilot only; Google/external calendars are not connected"
            let sources = values.prefix(15).map { item in
                StudyChatSource(id: item.value.id, title: item.value.title, detail: (item.external?.allDay == true ? "All day" : item.value.start.formatted(date: .abbreviated, time: .shortened)) + " · " + item.value.source, kind: item.local == nil && item.external == nil ? "assignment" : "calendar", localID: item.local?.id ?? UUID(uuidString: String(item.value.id.split(separator: ":").last ?? "")), date: item.value.start)
            }
            let lines = sources.map { "• \($0.title) — \($0.detail)" }.joined(separator: "\n")
            return .init(text: values.isEmpty ? "No events or deadlines found for \(label) in \(scope)." : "\(values.count) events or deadlines for \(label) in \(scope):\n\n" + lines + (values.count > 15 ? "\n\nShowing the first 15. Open Calendar for more." : ""), sources: sources)
        }
        guard useStudyContext else { return .init(text: "Enable Use my study tasks in Context & sources so I can check saved assignments.", sources: []) }
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        var tasks = try context.fetch(FetchDescriptor<Assignment>()).map { item in WorkspaceFactTask(record: item.record, subject: subjects.first { $0.id == item.subjectID }?.name ?? "") }
        var scope = "Only saved StudyPilot assignments were checked. Connect and select assignment calendars to include Google deadlines."
        if let planning, planning.hasAccess {
            try planning.refresh()
            let deadlines = planning.taskCandidates()
            tasks += deadlines.map { item in
                let calendarName = planning.events.first(where: { $0.id == item.id }).flatMap { event in planning.calendars.first { $0.id == event.calendarID }?.title } ?? "Synced calendar"
                let source = StudyChatSource(id: item.id, title: item.title, detail: "Due \(item.deadline.formatted(date: .abbreviated, time: .shortened)) · \(calendarName) · calendar deadline; completion not tracked", kind: "calendar", date: item.deadline)
                return WorkspaceFactTask(record: AssignmentRecord(title: item.title, details: item.details, dueDate: item.deadline), subject: StudyUnderstanding.subjectHint(title: item.title), calendarSource: source)
            }
            scope = "Calendar deadlines checked in the planner window: last 7 days through the next \(planning.settings.preferences.days) days, from selected assignment calendars. Google updates depend on macOS Calendar sync."
        }
        let answer = WorkspaceFacts.taskAnswer(request, tasks: tasks, now: now, query: query) ?? .init(text: "I couldn't check that request. Please try a specific task or date.", sources: [])
        return .init(text: answer.text + "\n\n" + scope, sources: answer.sources)
    }
    private func entries(in range: DateInterval) throws -> [CalendarChatEntry] {
        guard let context, let planning else { throw PlanningError.invalid("The calendar is still opening. Try again in a moment.") }
        let local = try context.fetch(FetchDescriptor<PlannerEvent>()).map(\.record)
        let assignments = try context.fetch(FetchDescriptor<Assignment>()).map(\.record)
        let subjects = try context.fetch(FetchDescriptor<Subject>())
        func subject(_ title: String, id: UUID?, taskID: String?) -> String {
            let linked = assignments.first { "local:\($0.id.uuidString)" == taskID }
            let name = subjects.first { $0.id == (id ?? linked?.subjectID) }?.name ?? ""
            return StudyUnderstanding.subjectHint(title: title, subject: name)
        }
        let external = planning.hasAccess ? try planning.chatEvents(in: range) : []
        let completed = Set(assignments.filter { $0.status == TaskStatus.done.rawValue }.map { "local:\($0.id.uuidString)" })
        func deadline(_ taskID: String?, notes: String) -> Date? {
            if let item = assignments.first(where: { "local:\($0.id.uuidString)" == taskID }) { return item.dueDate }
            if let item = planning.taskCandidates().first(where: { $0.id == taskID }) { return item.deadline }
            return StudyBlockTracking.read(notes).deadline ?? taskID.flatMap { planning.settings.taskOverrides[$0]?.deadline }
        }
        var result: [CalendarChatEntry] = local.compactMap { item in
            let end = item.startDate.addingTimeInterval(Double(item.durationMinutes * 60))
            guard item.startDate < range.end && end > range.start else { return nil }
            let taskID = PlannedStudyBlock.taskID(in: item.details)
            let movable = StudyBlockTracking.read(item.details).completedAt == nil && !completed.contains(taskID ?? "") && (!studyBlocksOnly || taskID != nil)
            return CalendarChatEntry(value: .init(id: "local-event:\(item.id)", title: item.title, start: item.startDate, end: end, source: "StudyPilot", subject: subject(item.title, id: item.subjectID, taskID: taskID), movable: movable, deadline: deadline(taskID, notes: item.details), taskID: taskID), local: item, external: nil, busy: true)
        }
        result += external.map { item in
            let movable = (item.ownTaskID != nil || !planning.settings.deadlineCalendarIDs.contains(item.calendarID)) && item.writable && !item.recurring && !item.allDay && StudyBlockTracking.read(item.notes).completedAt == nil && !completed.contains(item.ownTaskID ?? "") && (!studyBlocksOnly || item.ownTaskID != nil)
            let selectedDeadline = planning.settings.taskOverrides[item.id]?.selected == true
            let busy = item.ownTaskID != nil || (!item.free && !selectedDeadline && (planning.settings.busyCalendarIDs.contains(item.calendarID) || planning.settings.destinationID == item.calendarID))
            return CalendarChatEntry(value: .init(id: item.id, title: item.title, start: item.start, end: item.end, source: planning.calendars.first { $0.id == item.calendarID }?.title ?? "Synced calendar", subject: StudyUnderstanding.subjectHint(title: item.title), movable: movable, busy: busy, deadline: deadline(item.ownTaskID, notes: item.notes), taskID: item.ownTaskID), local: nil, external: item, busy: busy)
        }
        result += assignments.filter { $0.status != TaskStatus.done.rawValue && range.contains($0.dueDate) }.map { item in
            CalendarChatEntry(value: .init(id: "deadline:\(item.id)", title: item.title, start: item.dueDate, end: item.dueDate.addingTimeInterval(60), source: "Assignment deadline", subject: subject(item.title, id: item.subjectID, taskID: nil), movable: false, busy: false), local: nil, external: nil, busy: false)
        }
        return result.sorted { $0.value.start == $1.value.start ? $0.value.id < $1.value.id : $0.value.start < $1.value.start }
    }
    func propose(_ move: CalendarChatResponse.Move, snapshot: CalendarChatSnapshot, threadID: UUID) throws {
        pending = nil
        guard enabled, let item = snapshot.aliases[move.eventID], let entry = snapshot.entries.first(where: { $0.value.id == item.id }), let planning else { throw PlanningError.invalid("The reply did not identify an event from the current calendar. No changes were made. Name the event and try again.") }
        guard item.movable else { throw PlanningError.invalid("This event cannot be moved from chat. Choose a writable, single event; assignment deadlines stay unchanged.") }
        let now = Date(), start: Date
        if let text = move.start { start = try CalendarChat.date(text) }
        else {
            let horizon = Calendar.current.date(byAdding: .day, value: planning.settings.preferences.days, to: Calendar.current.startOfDay(for: now))!
            let deadline = min(item.deadline ?? horizon, horizon)
            let busy = try entries(in: DateInterval(start: Calendar.current.startOfDay(for: now), end: horizon)).filter { $0.busy && $0.value.id != item.id }.map { PlanningBusyTime(start: $0.value.start, end: $0.value.end, taskID: $0.value.taskID) }
            let seconds = item.end.timeIntervalSince(item.start)
            guard seconds.truncatingRemainder(dividingBy: 300) == 0, let found = try StudyBlockTracking.nextStart(minutes: Int(seconds / 60), deadline: deadline, busy: busy, preferences: planning.settings.preferences, now: now) else { throw PlanningError.invalid("No complete free study slot fits before the deadline. Choose an exact time or adjust your study hours. Automatic slot finding supports sessions up to two hours.") }
            start = found
        }
        let end = start.addingTimeInterval(item.end.timeIntervalSince(item.start))
        let window = DateInterval(start: Calendar.current.startOfDay(for: start), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!)
        let busy = try entries(in: window).filter { $0.busy && $0.value.id != item.id }.map { PlanningBusyTime(start: $0.value.start, end: $0.value.end) }
        try CalendarChat.validateMove(item, to: start, busy: busy, now: now)
        pending = CalendarChatProposal(threadID: threadID, entry: entry, start: start)
    }
    func apply() throws -> String {
        guard let proposal = pending, let context, let planning, enabled, !context.hasChanges else { throw PlanningError.invalid("Finish saving your current edit, then request a fresh move.") }
        if !planning.hasAccess && !planning.settings.busyCalendarIDs.isEmpty { throw PlanningError.invalid("Reconnect your calendars before moving this event so commitments can be checked.") }
        let item = proposal.entry.value
        let window = DateInterval(start: min(Calendar.current.startOfDay(for: item.start), Calendar.current.startOfDay(for: proposal.start)), end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(item.end, proposal.end)))!)
        guard window.duration < 366 * 86_400 else { throw PlanningError.invalid("Choose a date within a year of the existing event.") }
        let fresh = try entries(in: window)
        guard let current = fresh.first(where: { $0.value.id == item.id }), current.local == proposal.entry.local, current.external == proposal.entry.external, current.value == item else { pending = nil; throw PlanningError.invalid("This event or its deadline changed. Ask for a fresh proposal before moving it.") }
        let busy = fresh.filter { $0.busy && $0.value.id != item.id }.map { PlanningBusyTime(start: $0.value.start, end: $0.value.end) }
        try CalendarChat.validateMove(current.value, to: proposal.start, busy: busy, now: Date())
        if let record = current.local {
            guard let event = try context.fetch(FetchDescriptor<PlannerEvent>()).first(where: { $0.id == record.id }) else { throw PlanningError.invalid("This event no longer exists.") }
            var changed = record
            if let reminder = record.reminderDate { changed.reminderDate = reminder.addingTimeInterval(proposal.start.timeIntervalSince(record.startDate)) }
            changed.startDate = proposal.start
            if item.taskID != nil { var tracking = StudyBlockTracking.read(record.details); tracking.previousStart = record.startDate; changed.details = tracking.writing(to: record.details) }
            event.apply(changed)
            do { try context.save() } catch { event.apply(record); throw error }
            Task { await ReminderService.shared.reconcile(context: context) }
        } else if let external = current.external { try planning.moveFromChat(external, to: proposal.start) }
        else { throw PlanningError.invalid("Assignment deadlines cannot be moved from chat.") }
        // Clear immediately after committing. A refresh or history-save failure must never offer a duplicate retry.
        pending = nil
        let text = "Moved \(item.title) from \(item.start.formatted(date: .abbreviated, time: .shortened)) to \(proposal.start.formatted(date: .abbreviated, time: .shortened)) in \(item.source)." + (current.external != nil ? " Google/calendar sync is handled by macOS Calendar." : "")
        status = text
        visible = (try? entries(in: range)) ?? visible
        return text
    }
}
