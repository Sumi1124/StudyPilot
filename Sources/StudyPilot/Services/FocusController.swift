import Foundation
import Observation
import SwiftData
import StudyPilotCore
import StudyPilotData

@MainActor @Observable final class FocusController {
    var state: FocusState?
    var now = Date()
    var error: String?
    var completionMessage: String?
    private var completionSaveFailed = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "activeFocus"), let restored = try? JSONDecoder().decode(FocusState.self, from: data), restored.plannedSeconds.isFinite, (60...14_400).contains(restored.plannedSeconds), (0...restored.plannedSeconds).contains(restored.remainingAtAnchor) { state = restored }
    }
    var remaining: Double { state?.remaining(at: now) ?? 0 }
    var isRunning: Bool { state?.anchorDate != nil }
    func start(minutes: Int, subjectID: UUID?, isBreak: Bool = false) {
        guard state == nil else { return }
        now = Date(); completionMessage = nil; completionSaveFailed = false
        state = FocusState(subjectID: subjectID, seconds: Double(minutes * 60), now: now, isBreak: isBreak)
        persist(); refreshNotification()
    }
    func pause() { now = Date(); state?.pause(at: now); persist(); ReminderService.shared.cancelFocus() }
    func resume() { now = Date(); state?.resume(at: now); persist(); refreshNotification() }
    func tick(context: ModelContext) {
        now = Date()
        if !completionSaveFailed, let state, state.anchorDate != nil, state.remaining(at: now) <= 0 { finish(context: context) }
    }
    func finish(context: ModelContext) {
        guard let state else { return }
        now = Date()
        let complete = state.remaining(at: now) <= 0
        if !state.isBreak && state.elapsed(at: now) >= 1 {
            do {
                // Stable session IDs make completion safe to retry after a save failure or a crash.
                let existing = try context.fetch(FetchDescriptor<StudySession>()).contains { $0.id == state.id }
                if !existing {
                    let ended = complete ? (state.completionDate ?? now) : now
                    context.insert(StudySession(StudySessionRecord(id: state.id, subjectID: state.subjectID, startedAt: state.startedAt, endedAt: ended, durationSeconds: state.elapsed(at: now), plannedSeconds: state.plannedSeconds, completed: complete)))
                    try context.save()
                }
            } catch { context.rollback(); completionSaveFailed = true; self.error = "Your timer is preserved. The session could not be saved: \(error.localizedDescription)"; return }
        }
        completionMessage = state.isBreak ? "Break complete. Ready when you are." : complete ? "Session complete. A little progress, well earned." : "Your study time has been saved."
        self.state = nil; completionSaveFailed = false; persist(); ReminderService.shared.cancelFocus()
    }
    private func persist() {
        if let state {
            do { defaults.set(try JSONEncoder().encode(state), forKey: "activeFocus") }
            catch { self.error = "Could not preserve the timer: \(error.localizedDescription)" }
        } else { defaults.removeObject(forKey: "activeFocus") }
    }
    private func refreshNotification() {
        guard let state, let date = state.completionDate else { return }
        Task { await ReminderService.shared.scheduleFocus(at: date, isBreak: state.isBreak) }
    }
}
