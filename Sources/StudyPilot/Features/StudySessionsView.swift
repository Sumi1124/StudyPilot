import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct StudySessionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarPlanningService.self) private var service
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \PlannerEvent.startDate) private var events: [PlannerEvent]
    @State private var showCompleted = false
    private var localBlocks: [PlannerEvent] {
        events.filter { PlannedStudyBlock.taskID(in: $0.details) != nil && !service.isTaskFinished(PlannedStudyBlock.taskID(in: $0.details)) && (showCompleted || StudyBlockTracking.read($0.details).completedAt == nil) }
    }
    private var externalBlocks: [CalendarPlanningEvent] {
        service.events.filter { $0.ownTaskID != nil && !service.isTaskFinished($0.ownTaskID) && (showCompleted || StudyBlockTracking.read($0.notes).completedAt == nil) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Study blocks", systemImage: "checklist").font(.headline)
                Spacer()
                Toggle("Show completed", isOn: $showCompleted).toggleStyle(.checkbox)
                Button("Check unfinished") { service.checkUnfinished(context: context, force: true) }
                    .disabled(!service.automaticallyReschedules || service.working)
            }
            Text("Tick a block when you finish that session. Assignment completion is tracked separately in Assignments.").font(.caption).foregroundStyle(.secondary)
            if let message = service.completionCleanupMessage { Text(message).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let message = service.automationMessage { Text(message).font(.callout).textSelection(.enabled) }
            if localBlocks.isEmpty && externalBlocks.isEmpty { Text("No unchecked study blocks. Use Plan my study to create your schedule.").foregroundStyle(.secondary) }
            ForEach(localBlocks.prefix(100)) { event in
                row(title: event.title, start: event.startDate, minutes: event.durationMinutes, notes: event.details, source: "StudyPilot") { completed in
                    do { try service.setCompleted(completed, local: event, context: context) } catch { app.error = error.localizedDescription }
                }
            }
            ForEach(externalBlocks.prefix(100)) { event in
                row(title: event.title, start: event.start, minutes: Int(event.end.timeIntervalSince(event.start) / 60), notes: event.notes, source: "Calendar") { completed in
                    do { try service.setCompleted(completed, external: event) } catch { app.error = error.localizedDescription }
                }
            }
            if localBlocks.count > 100 || externalBlocks.count > 100 { Text("Showing the first 100 blocks from each source.").font(.caption).foregroundStyle(.secondary) }
        }.pilotCard()
    }
    private func row(title: String, start: Date, minutes: Int, notes: String, source: String, change: @escaping (Bool) -> Void) -> some View {
        let tracking = StudyBlockTracking.read(notes)
        let completed = tracking.completedAt != nil
        return HStack(alignment: .top, spacing: 14) {
            Toggle(isOn: Binding(get: { completed }, set: { value in change(value) })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).strikethrough(completed).font(.headline)
                    Text("\(source) · \(start.formatted(date: .abbreviated, time: .shortened)) · \(minutes) min").font(.caption).foregroundStyle(.secondary)
                    if let previous = tracking.previousStart { Text("Rescheduled from \(previous.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Color.pilot) }
                    if !completed && start.addingTimeInterval(Double(minutes * 60)) <= app.now { Text("Unfinished · waiting for a new time").font(.caption).foregroundStyle(.orange) }
                }
            }.toggleStyle(.checkbox)
            Spacer()
            if let id = PlannedStudyBlock.taskID(in: notes) { FinishStudyTaskButton(taskID: id, title: title) }
        }.padding(.vertical, 5)
    }
}

struct FinishStudyTaskButton: View {
    @Environment(AppState.self) private var app
    @Environment(CalendarPlanningService.self) private var planning
    @Environment(\.modelContext) private var context
    let taskID: String
    let title: String
    var body: some View {
        Button("Finish task") { app.finishTask(id: taskID, title: title, context: context) }
            .disabled(planning.isTaskFinished(taskID))
            .help("Finish the whole assignment and clear every linked study session. Undo is available for 90 seconds.")
            .accessibilityLabel("Finish task linked to \(title) and clear its study sessions")
    }
}
