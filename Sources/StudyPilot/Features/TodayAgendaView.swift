import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct TodayAgendaView: View {
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @Environment(CalendarPlanningService.self) private var planning
    @Environment(\.modelContext) private var context
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery(sort: \PlannerEvent.startDate) private var events: [PlannerEvent]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var offset = 0
    @State private var editing: Assignment?
    @State private var editingEvent: PlannerEvent?
    @State private var refreshError: String?
    private var day: Date { Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: app.now))! }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: day)! }
    private var tasks: [Assignment] { assignments.filter { !$0.isDone && $0.dueDate >= day && $0.dueDate < end } }
    private var localEvents: [PlannerEvent] { events.filter { !planning.isTaskFinished(PlannedStudyBlock.taskID(in: $0.details)) && $0.startDate < end && $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)) > day } }
    private var externalEvents: [CalendarPlanningEvent] { planning.events.filter { !planning.isTaskFinished($0.ownTaskID) && $0.start < end && $0.end > day } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Your agenda", systemImage: "calendar.day.timeline.left").font(.title3.bold())
                Spacer()
                Picker("Day", selection: $offset) { Text("Today").tag(0); Text("Tomorrow").tag(1) }.pickerStyle(.segmented).frame(width: 200)
                Button("Open calendar") { app.openCalendar(day) }
            }
            let overdue = assignments.filter { !$0.isDone && $0.dueDate < app.now }
            if !overdue.isEmpty {
                HStack { Label("\(overdue.count) overdue assignment\(overdue.count == 1 ? "" : "s")", systemImage: "exclamationmark.circle").foregroundStyle(.orange); Spacer(); Button("Review overdue") { app.assignmentTimeFilter = .overdue; app.section = .assignments } }.font(.callout)
            }
            Text("Due \(offset == 0 ? "today" : "tomorrow") · \(tasks.count) task\(tasks.count == 1 ? "" : "s") · \(tasks.reduce(0) { $0 + $1.estimatedMinutes }) min estimated effort").font(.subheadline.bold())
            if tasks.isEmpty { Text("No unfinished assignments due on this day.").foregroundStyle(.secondary).font(.callout) }
            ForEach(tasks.prefix(6)) { task in
                AssignmentRow(assignment: task, subject: subjects.first { $0.id == task.subjectID }) { editing = task }
            }
            if tasks.count > 6 { Button("View all \(tasks.count) assignments") { app.assignmentTimeFilter = offset == 0 ? .today : .tomorrow; app.section = .assignments } }
            Divider()
            HStack { Text("Scheduled time").font(.subheadline.bold()); Spacer(); if planning.hasAccess { Button("Refresh") { refresh() }.font(.caption) } }
            if localEvents.isEmpty && externalEvents.isEmpty { Text("No scheduled events. Plan some study time around your deadlines.").font(.callout).foregroundStyle(.secondary) }
            ForEach(localEvents.prefix(8)) { event in
                HStack(spacing: 12) {
                    let tracked = PlannedStudyBlock.taskID(in: event.details) != nil
                    if tracked {
                        Toggle("Complete \(event.title)", isOn: Binding(get: { StudyBlockTracking.read(event.details).completedAt != nil }, set: { done in
                            do { try planning.setCompleted(done, local: event, context: context) } catch { app.error = error.localizedDescription }
                        })).labelsHidden().toggleStyle(.checkbox)
                    } else { Image(systemName: event.kind == "Exam" ? "graduationcap" : "calendar").foregroundStyle(Color.pilot) }
                    VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.callout.bold()).strikethrough(StudyBlockTracking.read(event.details).completedAt != nil); Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) · \(event.durationMinutes) min · StudyPilot").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Focus") { if focus.state == nil { focus.start(minutes: min(60, max(5, event.durationMinutes)), subjectID: event.subjectID) }; app.section = .focus }
                    if let id = PlannedStudyBlock.taskID(in: event.details) { FinishStudyTaskButton(taskID: id, title: event.title) }
                    Button("Edit") { editingEvent = event }
                }.padding(.vertical, 4)
            }
            ForEach(externalEvents.prefix(8)) { event in
                HStack(spacing: 12) {
                    if event.ownTaskID != nil {
                        Toggle("Complete \(event.title)", isOn: Binding(get: { StudyBlockTracking.read(event.notes).completedAt != nil }, set: { done in
                            do { try planning.setCompleted(done, external: event) } catch { app.error = error.localizedDescription }
                        })).labelsHidden().toggleStyle(.checkbox)
                    } else { Image(systemName: "calendar").foregroundStyle(Color.pilot) }
                    VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.callout.bold()); Text("\(event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)) · \(planning.calendars.first { $0.id == event.calendarID }?.title ?? "Synced calendar")").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let id = event.ownTaskID { FinishStudyTaskButton(taskID: id, title: event.title) }
                    Button("Ask AI") { app.ask("Help me with the calendar event \(event.title) on \(event.start.formatted(date: .abbreviated, time: .shortened)).") }
                }.padding(.vertical, 4)
            }
            if localEvents.count > 8 || externalEvents.count > 8 { Text("Showing the first eight events from each source.").font(.caption).foregroundStyle(.secondary) }
            if !planning.hasAccess { Text("Local events only. Connect calendars in Plan my study to include Google.").font(.caption).foregroundStyle(.secondary) }
            if let refreshError { Text(refreshError).font(.caption).foregroundStyle(.red) }
            HStack { Button("Plan my study", systemImage: "sparkles") { app.showingStudyPlanner = true }; Button("Ask about \(offset == 0 ? "today" : "tomorrow")", systemImage: "bubble.left") { app.ask("What is on my calendar \(offset == 0 ? "today" : "tomorrow")?") } }
        }.pilotCard().sheet(item: $editing) { AssignmentEditor(assignment: $0) }.sheet(item: $editingEvent) { EventEditor(event: $0) }
            .task { if planning.hasAccess { refresh() } }
    }
    private func refresh() { do { try planning.refresh(); refreshError = nil } catch { refreshError = error.localizedDescription } }
}
