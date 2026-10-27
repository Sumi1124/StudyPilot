import Foundation
import Observation
@preconcurrency import EventKit
import StudyPilotCore
import SwiftData
import StudyPilotData

struct ConnectedPlanningCalendar: Identifiable {
    let id: String
    let title: String
    let account: String
    let writable: Bool
    var label: String { "\(title) · \(account)" }
}

struct CalendarPlanningEvent: Identifiable, Equatable {
    let id: String
    let eventIdentifier: String
    let calendarID: String
    let title: String
    let notes: String
    let start: Date
    let end: Date
    let allDay: Bool
    let free: Bool
    let ownTaskID: String?
    let modified: Date?
    let writable: Bool
    let recurring: Bool
    var deadline: Date { allDay ? end.addingTimeInterval(-60) : start }
}

struct CalendarPlanningSettings: Codable {
    var routines: [StudyRoutine]?
    var completedTasks: [String: CompletedStudyTask]?
    var sessionEventIDs: [String: Set<String>]?
    var autoReschedule: Bool?
    var preferences = PlanningPreferences()
    var deadlineCalendarIDs: Set<String> = []
    var busyCalendarIDs: Set<String> = []
    var hasChosenBusyCalendars = false
    var destinationID = ""
    var taskOverrides: [String: PlanningTask] = [:]
}

@MainActor @Observable final class CalendarPlanningService {
    let store = EKEventStore()
    var completionCleanupMessage: String?
    var calendarRevision = 0
    var lastCompletionCleanup = Date.distantPast
    private var settingsURL: URL?
    var settings = CalendarPlanningSettings()
    var calendars: [ConnectedPlanningCalendar] = []
    var events: [CalendarPlanningEvent] = []
    var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    var lastRefresh: Date?
    var error: String?
    var status: String?
    var working = false
    var needsRefresh = false
    var automationMessage: String?
    private var lastAutomationCheck = Date.distantPast
    var automaticallyReschedules: Bool { settings.autoReschedule ?? true }

    func configure(folder: URL) {
        guard settingsURL == nil else { return }
        let url = folder.appendingPathComponent("CalendarPlanning.json")
        settingsURL = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            settings = try JSONDecoder().decode(CalendarPlanningSettings.self, from: Data(contentsOf: url))
            try settings.preferences.validate()
        } catch { self.error = "Planning preferences could not be read: \(error.localizedDescription). The saved file has not been changed." }
    }
    func saveSettings(tasks: [PlanningTask]? = nil) throws {
        if let tasks {
            for task in tasks { settings.taskOverrides[task.id] = task }
            // Keep bounded preferences; calendar event descriptions are not persisted here.
            if settings.taskOverrides.count > 1000 {
                settings.taskOverrides = settings.taskOverrides.filter { $0.value.deadline > Date().addingTimeInterval(-30 * 86_400) }
            }
        }
        guard let url = settingsURL else { return }
        var copy = settings
        for key in copy.taskOverrides.keys { copy.taskOverrides[key]?.details = "" }
        try JSONEncoder().encode(copy).write(to: url, options: .atomic)
    }
    func connect() async {
        working = true; error = nil
        defer { working = false }
        do {
            hasAccess = try await store.requestFullAccessToEvents()
            guard hasAccess else { throw PlanningError.invalid("Calendar access was not granted. Enable StudyPilot in System Settings → Privacy & Security → Calendars, then reconnect.") }
            try refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() throws {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { throw PlanningError.invalid("Connect your calendars to read Google assignments and check availability.") }
        store.refreshSourcesIfNecessary()
        calendars = store.calendars(for: .event).map { .init(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, writable: $0.allowsContentModifications) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        let known = Set(calendars.map(\.id))
        settings.deadlineCalendarIDs.formIntersection(known)
        // First connection checks all calendars for conflicts. Users can narrow this explicitly.
        if !settings.hasChosenBusyCalendars { settings.busyCalendarIDs = known; settings.hasChosenBusyCalendars = true }
        settings.busyCalendarIDs.formIntersection(known)
        events = try readEvents()
        lastRefresh = Date(); needsRefresh = false
    }
    private func readEvents(range: DateInterval? = nil) throws -> [CalendarPlanningEvent] {
        let now = Date(), calendar = Calendar.current
        let start = range?.start ?? calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
        let end = range?.end ?? calendar.date(byAdding: .day, value: settings.preferences.days, to: calendar.startOfDay(for: now))!
        var selectedIDs = settings.deadlineCalendarIDs.union(settings.busyCalendarIDs)
        if !settings.destinationID.isEmpty { selectedIDs.insert(settings.destinationID) }
        let selectedCalendars = store.calendars(for: .event).filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !selectedCalendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selectedCalendars)
        let values = store.events(matching: predicate).filter { event in
            event.status != .canceled && !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }
        guard values.count <= 20_000 else { throw PlanningError.invalid("This date range contains too many events. Choose a shorter planning window.") }
        var seen = Set<String>()
        return values.compactMap { event in
            guard let start = event.startDate, let end = event.endDate, end >= start else { return nil }
            let itemID = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
            let occurrence = event.hasRecurrenceRules ? ":\((event.occurrenceDate ?? start).timeIntervalSince1970)" : ""
            let id = "calendar:\(event.calendar.calendarIdentifier):\(itemID)\(occurrence)"
            guard seen.insert(id).inserted else { return nil }
            let owned = event.url?.scheme == "studypilot" && event.url?.host == "plan"
            return CalendarPlanningEvent(id: id, eventIdentifier: event.eventIdentifier ?? "", calendarID: event.calendar.calendarIdentifier,
                title: event.title ?? "Untitled calendar event", notes: event.notes ?? "", start: start, end: end,
                allDay: event.isAllDay, free: event.availability == .free,
                ownTaskID: owned ? PlannedStudyBlock.taskID(in: event.notes ?? "") : nil, modified: event.lastModifiedDate, writable: event.calendar.allowsContentModifications, recurring: event.hasRecurrenceRules)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
    func chatEvents(in range: DateInterval) throws -> [CalendarPlanningEvent] {
        try refresh()
        return try readEvents(range: range)
    }
    func moveFromChat(_ snapshot: CalendarPlanningEvent, to start: Date) throws {
        guard let event = store.event(withIdentifier: snapshot.eventIdentifier),
              event.calendar.calendarIdentifier == snapshot.calendarID, event.title == snapshot.title,
              (event.notes ?? "") == snapshot.notes, event.startDate == snapshot.start, event.endDate == snapshot.end,
              event.lastModifiedDate == snapshot.modified, event.calendar.allowsContentModifications,
              !event.hasRecurrenceRules, !event.isAllDay, event.status != .canceled else {
            throw PlanningError.invalid("This calendar event changed or cannot be moved. Ask for a fresh proposal.")
        }
        let shift = start.timeIntervalSince(snapshot.start)
        if snapshot.ownTaskID != nil {
            var progress = StudyBlockTracking.read(snapshot.notes); progress.previousStart = snapshot.start
            event.notes = progress.writing(to: snapshot.notes)
        }
        for alarm in event.alarms ?? [] { if let date = alarm.absoluteDate { alarm.absoluteDate = date.addingTimeInterval(shift) } }
        event.startDate = start; event.endDate = snapshot.end.addingTimeInterval(shift)
        do { try store.save(event, span: .thisEvent, commit: true) }
        catch { store.reset(); throw error }
        needsRefresh = true
    }
    func taskCandidates() -> [PlanningTask] {
        events.filter { settings.deadlineCalendarIDs.contains($0.calendarID) && $0.ownTaskID == nil && !isTaskFinished($0.id) }.map { event in
            var task = PlanningTask(id: event.id, title: event.title, details: event.notes, deadline: event.deadline, selected: false)
            if let saved = settings.taskOverrides[task.id] {
                task.minutes = saved.minutes; task.priority = saved.priority; task.steps = saved.steps; task.selected = saved.selected
            }
            return task
        }
    }
    func busyTimes(excludingTasks ids: Set<String>) -> [PlanningBusyTime] {
        events.filter {
            // Existing StudyPilot blocks always count, even if their calendar is not a busy source.
            ($0.ownTaskID != nil || settings.busyCalendarIDs.contains($0.calendarID) || $0.calendarID == settings.destinationID)
                && !ids.contains($0.id) && (!$0.free || $0.ownTaskID != nil) && $0.end > $0.start
        }.map { .init(start: $0.start, end: $0.end, taskID: $0.ownTaskID) }
    }
    func validatePreview(_ plan: StudyPlan, tasks: [PlanningTask]) throws {
        guard !needsRefresh else { throw PlanningError.invalid("Refresh your calendars and generate a new preview first.") }
        let previous = events
        let fresh = hasAccess ? try readEvents() : events
        // Any relevant change, including new busy events, requires a fresh preview.
        guard previous == fresh else { events = fresh; needsRefresh = true; throw PlanningError.invalid("Your calendar changed after this preview. Refresh and generate the plan again to avoid conflicts.") }
        let selected = Set(tasks.filter(\.selected).map(\.id))
        let busy = busyTimes(excludingTasks: selected)
        guard plan.blocks.allSatisfy({ block in block.start > Date() && !busy.contains { $0.overlaps(start: block.start, end: block.end) } }) else {
            throw PlanningError.invalid("A study block is now in the past or conflicts with your calendar. Generate a fresh plan.")
        }
    }
    func publish(_ plan: StudyPlan, tasks: [PlanningTask]) throws {
        guard hasAccess, let calendar = store.calendar(withIdentifier: settings.destinationID), calendar.allowsContentModifications else {
            throw PlanningError.invalid("Connect your calendars and choose a writable destination calendar before adding the plan.")
        }
        guard !plan.blocks.isEmpty else { return }
        try validatePreview(plan, tasks: tasks)
        working = true
        defer { working = false }
        var published: [(String, EKEvent)] = []
        do {
            for block in plan.blocks {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar; event.title = "Study: \(block.title)"
                event.startDate = block.start; event.endDate = block.end; event.notes = block.notes
                event.url = URL(string: "studypilot://plan/\(block.id.uuidString)")
                event.availability = .busy
                try store.save(event, span: .thisEvent, commit: false)
                published.append((block.taskID, event))
            }
            try store.commit()
        } catch { store.reset(); needsRefresh = true; throw error }
        for (taskID, event) in published {
            if let id = event.eventIdentifier {
                if settings.sessionEventIDs == nil { settings.sessionEventIDs = [:] }
                settings.sessionEventIDs?[taskID, default: []].insert(id)
            }
        }
        // The events are already committed; a registry failure must not invite duplicate publication.
        do { try saveSettings() } catch { completionCleanupMessage = "Sessions were added, but their cleanup registry could not be saved: \(error.localizedDescription)" }
        // A successful commit is final even if a subsequent refresh fails; never invite a duplicate retry.
        events = (try? readEvents()) ?? events; lastRefresh = Date()
        status = "Added \(plan.blocks.count) study blocks to \(calendar.title). Google sync is handled by macOS Calendar."
    }
    func setCompleted(_ completed: Bool, local event: PlannerEvent, context: ModelContext) throws {
        let original = event.details
        var tracking = StudyBlockTracking.read(original)
        tracking.completedAt = completed ? Date() : nil
        event.details = tracking.writing(to: original)
        do { try context.save() } catch { event.details = original; throw error }
        Task { await ReminderService.shared.reconcile(context: context) }
    }
    func setCompleted(_ completed: Bool, external snapshot: CalendarPlanningEvent) throws {
        guard let event = store.event(withIdentifier: snapshot.eventIdentifier),
              event.notes == snapshot.notes, event.startDate == snapshot.start, event.endDate == snapshot.end,
              event.calendar.allowsContentModifications, !event.hasRecurrenceRules,
              event.url?.scheme == "studypilot", event.url?.host == "plan" else {
            throw PlanningError.invalid("This block changed or is read-only. Refresh your calendars before checking it off.")
        }
        var tracking = StudyBlockTracking.read(snapshot.notes)
        tracking.completedAt = completed ? Date() : nil
        event.notes = tracking.writing(to: snapshot.notes)
        do { try store.save(event, span: .thisEvent, commit: true) }
        catch { store.reset(); throw error }
        events = (try? readEvents()) ?? events
        calendarRevision += 1
    }
    /// Runs on the main context; all mutations are synchronous so user edits cannot interleave.
    func checkUnfinished(context: ModelContext, force: Bool = false) {
        guard automaticallyReschedules, !working, !context.hasChanges,
              force || Date().timeIntervalSince(lastAutomationCheck) >= 60 else { return }
        lastAutomationCheck = Date()
        let now = Date()
        do {
            let local = try context.fetch(FetchDescriptor<PlannerEvent>())
            let assignments = try context.fetch(FetchDescriptor<Assignment>())
            let missedLocal = local.filter { StudyBlockTracking.isUnfinished(start: $0.startDate, minutes: $0.durationMinutes, notes: $0.details, now: now) }
            // Read external blocks on every check, including after wake/reopen. No permission prompts.
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess { try refresh() }
            else if hasAccess { hasAccess = false; events = [] }
            if !hasAccess && !settings.busyCalendarIDs.isEmpty {
                throw PlanningError.invalid("Reconnect calendars before automatically moving blocks around your commitments.")
            }
            let missedExternal = events.filter { $0.ownTaskID != nil && StudyBlockTracking.read($0.notes).completedAt == nil && $0.end <= now }
            guard !missedLocal.isEmpty || !missedExternal.isEmpty else { return }
            var taskMap = Dictionary(uniqueKeysWithValues: taskCandidates().map { ($0.id, $0) })
            for assignment in assignments {
                taskMap["local:\(assignment.id.uuidString)"] = PlanningTask(id: "local:\(assignment.id.uuidString)", title: assignment.title, deadline: assignment.dueDate)
            }
            let completedIDs = Set(assignments.filter { $0.status == TaskStatus.done.rawValue }.map { "local:\($0.id.uuidString)" }).union(settings.completedTasks?.keys.map { $0 } ?? [])
            var busy = busyTimes(excludingTasks: Set(settings.taskOverrides.values.filter(\.selected).map(\.id)).union(missedLocal.compactMap { PlannedStudyBlock.taskID(in: $0.details) }).union(missedExternal.compactMap(\.ownTaskID))).filter { $0.end > now }
            busy += local.map { PlanningBusyTime(start: $0.startDate, end: $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)), taskID: PlannedStudyBlock.taskID(in: $0.details)) }.filter { $0.end > now }
            var moved = 0, waiting = 0
            func target(taskID: String, notes: String, minutes: Int) throws -> Date? {
                guard !completedIDs.contains(taskID) else { return nil }
                let tracking = StudyBlockTracking.read(notes)
                // Live deadlines take precedence over the original deadline saved in the block.
                guard let deadline = taskMap[taskID]?.deadline ?? tracking.deadline ?? settings.taskOverrides[taskID]?.deadline else { waiting += 1; return nil }
                let date = try StudyBlockTracking.nextStart(minutes: minutes, deadline: deadline, busy: busy, preferences: settings.preferences, now: now)
                if date == nil { waiting += 1 }
                return date
            }
            for event in missedLocal.sorted(by: { $0.startDate < $1.startDate }) {
                guard let taskID = PlannedStudyBlock.taskID(in: event.details), let start = try target(taskID: taskID, notes: event.details, minutes: event.durationMinutes) else { continue }
                let original = event.record
                var tracking = StudyBlockTracking.read(event.details); tracking.previousStart = event.startDate
                event.details = tracking.writing(to: event.details)
                if let reminder = event.reminderDate { event.reminderDate = start.addingTimeInterval(reminder.timeIntervalSince(event.startDate)) }
                event.startDate = start
                do { try context.save() } catch { event.apply(original); throw error }
                busy.append(.init(start: start, end: start.addingTimeInterval(Double(event.durationMinutes * 60)), taskID: taskID)); moved += 1
            }
            for snapshot in missedExternal.sorted(by: { $0.start < $1.start }) {
                guard let taskID = snapshot.ownTaskID, !completedIDs.contains(taskID) else { continue }
                guard let event = store.event(withIdentifier: snapshot.eventIdentifier), event.notes == snapshot.notes,
                      event.startDate == snapshot.start, event.endDate == snapshot.end,
                      event.calendar.allowsContentModifications, !event.hasRecurrenceRules,
                      event.url?.scheme == "studypilot", event.url?.host == "plan" else { waiting += 1; continue }
                let minutes = Int(snapshot.end.timeIntervalSince(snapshot.start) / 60)
                guard let start = try target(taskID: taskID, notes: snapshot.notes, minutes: minutes) else { continue }
                var tracking = StudyBlockTracking.read(snapshot.notes); tracking.previousStart = snapshot.start
                event.notes = tracking.writing(to: snapshot.notes); event.startDate = start
                event.endDate = start.addingTimeInterval(snapshot.end.timeIntervalSince(snapshot.start))
                do { try store.save(event, span: .thisEvent, commit: true) } catch { store.reset(); throw error }
                busy.append(.init(start: start, end: event.endDate, taskID: taskID)); moved += 1
            }
            if hasAccess { events = try readEvents() }
            automationMessage = "\(moved) unfinished blocks rescheduled." + (waiting > 0 ? " \(waiting) need attention: check deadlines, available study hours, or calendar write access." : "")
            if moved > 0 { Task { await ReminderService.shared.reconcile(context: context) } }
        } catch { automationMessage = "Automatic rescheduling needs attention: \(error.localizedDescription)" }
    }

}
