import Foundation
import EventKit
import SwiftData
import StudyPilotCore
import StudyPilotData

extension CalendarPlanningService {
    func isTaskFinished(_ taskID: String?) -> Bool {
        guard let taskID else { return false }
        return settings.completedTasks?[taskID] != nil
    }
    func recordTaskCompletion(id: String, title: String, completed: Bool, at date: Date = Date()) throws {
        let before = settings.completedTasks
        if completed {
            guard settings.completedTasks?[id] == nil else { return }
            if settings.completedTasks == nil { settings.completedTasks = [:] }
            let needsAccess = id.hasPrefix("calendar:") || hasAccess || !settings.destinationID.isEmpty || !(settings.sessionEventIDs?[id]?.isEmpty ?? true) || events.contains { $0.ownTaskID == id }
            settings.completedTasks?[id] = CompletedStudyTask(title: title, completedAt: date, needsCalendarAccess: needsAccess)
        } else { settings.completedTasks?.removeValue(forKey: id) }
        do { try saveSettings() } catch { settings.completedTasks = before; throw error }
        calendarRevision += 1; needsRefresh = true
    }
    /// The durable completion queue survives closing the app. Deletion waits for the Undo window.
    func removeFinishedTaskSessions(context: ModelContext, now: Date = Date(), force: Bool = false) {
        guard !working, !context.hasChanges, force || now.timeIntervalSince(lastCompletionCleanup) >= 5 else { return }
        lastCompletionCleanup = now
        guard let records = settings.completedTasks else { return }
        do {
            let assignments = try context.fetch(FetchDescriptor<Assignment>())
            for (id, record) in records {
                // A restored backup or an editor can reopen a local assignment.
                if let localID = StudyTaskLink.localID(id), let assignment = assignments.first(where: { $0.id == localID }), assignment.status != TaskStatus.done.rawValue {
                    try recordTaskCompletion(id: id, title: record.title, completed: false)
                }
            }
            let ready = settings.completedTasks?.filter { $0.value.ready(at: now) } ?? [:]
            guard !ready.isEmpty else { return }
            // Retry disconnected/read-only calendars at most once per minute.
            lastCompletionCleanup = now.addingTimeInterval(55)
            let local = try context.fetch(FetchDescriptor<PlannerEvent>())
            let removing = local.filter { event in
                guard let id = PlannedStudyBlock.taskID(in: event.details) else { return false }
                return ready[id] != nil
            }
            for event in removing { context.delete(event) }
            do { try context.save() } catch { context.rollback(); throw error }
            let needsExternal = ready.contains { $0.value.needsCalendarAccess }
            if needsExternal {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                    throw PlanningError.invalid("Completed assignments are hidden from your plan. Reconnect calendars to remove their synced study sessions.")
                }
                store.refreshSourcesIfNecessary()
                let external = try linkedSessions(taskIDs: Set(ready.keys), now: now)
                // Validate the entire batch before staging any external deletion.
                guard external.allSatisfy({ $0.calendar.allowsContentModifications && !$0.hasRecurrenceRules && ($0.attendees?.isEmpty ?? true) }) else {
                    throw PlanningError.invalid("Some finished-task sessions are read-only, recurring, or have attendees. Remove those sessions in Calendar; StudyPilot will retry the others after access is fixed.")
                }
                do {
                    for event in external { try store.remove(event, span: .thisEvent, commit: false) }
                    if !external.isEmpty { try store.commit() }
                } catch { store.reset(); throw error }
            }
            let previousRegistry = settings.sessionEventIDs
            for id in ready.keys {
                settings.completedTasks?[id]?.cleaned = true
                settings.sessionEventIDs?.removeValue(forKey: id)
            }
            do { try saveSettings() } catch {
                settings.sessionEventIDs = previousRegistry
                for id in ready.keys { settings.completedTasks?[id]?.cleaned = false }
                throw error
            }
            events.removeAll { ready[$0.ownTaskID ?? ""] != nil }
            calendarRevision += 1; needsRefresh = true
            completionCleanupMessage = nil
            Task { await ReminderService.shared.reconcile(context: context) }
        } catch { completionCleanupMessage = "Session cleanup needs attention: \(error.localizedDescription)" }
    }
    private func linkedSessions(taskIDs: Set<String>, now: Date) throws -> [EKEvent] {
        var found: [String: EKEvent] = [:]
        func include(_ event: EKEvent) {
            guard let notes = event.notes, let taskID = PlannedStudyBlock.taskID(in: notes), taskIDs.contains(taskID),
                  StudyTaskLink.ownsSyncedSession(url: event.url, notes: notes, taskID: taskID), let id = event.eventIdentifier else { return }
            found[id] = event
        }
        // Registered sessions are found even if moved outside the usual planning dates.
        for taskID in taskIDs {
            for id in settings.sessionEventIDs?[taskID] ?? [] { if let event = store.event(withIdentifier: id) { include(event) } }
        }
        // Legacy sessions predate the registry. Search all accessible calendars, not only selected sources.
        // Each EventKit predicate stays within its four-year limit.
        let cal = Calendar.current
        for offset in [-4, 0] {
            let start = cal.date(byAdding: .year, value: offset, to: now)!
            let end = cal.date(byAdding: .year, value: 4, to: start)!
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = store.events(matching: predicate)
            guard events.count <= 100_000 else { throw PlanningError.invalid("Too many calendar events to check safely. Remove linked sessions in Apple Calendar.") }
            for event in events { include(event) }
        }
        return Array(found.values)
    }
}
