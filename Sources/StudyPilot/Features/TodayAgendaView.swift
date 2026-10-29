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
    @State private var expandedGroups: Set<String> = []
    private var day: Date { Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: app.now))! }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: day)! }
    private var tasks: [Assignment] { assignments.filter { !$0.isDone && $0.dueDate >= day && $0.dueDate < end } }
    private var localEvents: [PlannerEvent] { events.filter { !planning.isTaskFinished(PlannedStudyBlock.taskID(in: $0.details)) && $0.startDate < end && $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)) > day } }
    private var externalEvents: [CalendarPlanningEvent] { planning.events.filter { !planning.isTaskFinished($0.ownTaskID) && $0.start < end && $0.end > day } }
    private var localGroups: [LocalAgendaGroup] {
        Dictionary(grouping: localEvents) { event in
            PlannedStudyBlock.taskID(in: event.details).map { "local:\($0)" } ?? "local-event:\(event.id.uuidString)"
        }.map { LocalAgendaGroup(id: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { ($0.events.first?.startDate ?? .distantFuture) < ($1.events.first?.startDate ?? .distantFuture) }
    }
    private var externalGroups: [ExternalAgendaGroup] {
        Dictionary(grouping: externalEvents) { event in
            event.ownTaskID.map { "calendar:\($0)" } ?? "calendar-event:\(event.id)"
        }.map { ExternalAgendaGroup(id: $0.key, events: $0.value.sorted { $0.start < $1.start }) }
            .sorted { ($0.events.first?.start ?? .distantFuture) < ($1.events.first?.start ?? .distantFuture) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Agenda").font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("Day", selection: $offset) { Text("Today").tag(0); Text("Tomorrow").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                Button("Calendar") { app.openCalendar(day) }.buttonStyle(.link)
            }
            if !tasks.isEmpty {
                HStack { Text("Due \(offset == 0 ? "today" : "tomorrow")").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(tasks.count) task\(tasks.count == 1 ? "" : "s") · \(tasks.reduce(0) { $0 + $1.estimatedMinutes }) min estimated").font(.caption).foregroundStyle(.secondary) }
                ForEach(tasks.prefix(6)) { task in
                    AssignmentRow(assignment: task, subject: subjects.first { $0.id == task.subjectID }) { editing = task }
                }
                if tasks.count > 6 { Button("View all \(tasks.count) assignments") { app.assignmentTimeFilter = offset == 0 ? .today : .tomorrow; app.section = .assignments } }
                Divider()
            }
            HStack { Text("Study schedule").font(.system(size: 13, weight: .semibold)); Spacer(); if planning.hasAccess { Button("Refresh") { refresh() }.font(.caption) } }
            if localEvents.isEmpty && externalEvents.isEmpty { Text("No scheduled events. Plan some study time around your deadlines.").font(.callout).foregroundStyle(.secondary) }
            ForEach(localGroups.prefix(8)) { group in
                if group.events.count > 1, let first = group.events.first {
                    groupHeader(id: group.id, title: cleanTitle(first.title), count: group.events.count,
                                minutes: group.events.reduce(0) { $0 + $1.durationMinutes },
                                completed: group.events.filter { StudyBlockTracking.read($0.details).completedAt != nil }.count)
                    if expandedGroups.contains(group.id) {
                        ForEach(group.events) { localRow($0, grouped: true).padding(.leading, 14) }
                    }
                } else if let event = group.events.first { localRow(event, grouped: false) }
            }
            ForEach(externalGroups.prefix(8)) { group in
                if group.events.count > 1, let first = group.events.first {
                    groupHeader(id: group.id, title: cleanTitle(first.title), count: group.events.count,
                                minutes: group.events.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) },
                                completed: group.events.filter { StudyBlockTracking.read($0.notes).completedAt != nil }.count)
                    if expandedGroups.contains(group.id) {
                        ForEach(group.events) { externalRow($0, grouped: true).padding(.leading, 14) }
                    }
                } else if let event = group.events.first { externalRow(event, grouped: false) }
            }
            if localGroups.count > 8 || externalGroups.count > 8 { Button("More events in Calendar") { app.openCalendar(day) }.font(.caption) }
            if !planning.hasAccess { Text("Local events only. Connect calendars in Plan my study to include Google.").font(.caption).foregroundStyle(.secondary) }
            if let refreshError { Text(refreshError).font(.caption).foregroundStyle(.red) }
            HStack { Button("Plan study time", systemImage: "calendar.badge.clock") { app.showingStudyPlanner = true }; Button("Ask about \(offset == 0 ? "today" : "tomorrow")", systemImage: "bubble.left") { app.ask("What is on my calendar \(offset == 0 ? "today" : "tomorrow")?") } }.font(.caption).buttonStyle(.link)
        }.font(.callout).buttonStyle(.bordered).sheet(item: $editing) { AssignmentEditor(assignment: $0) }.sheet(item: $editingEvent) { EventEditor(event: $0) }
            .task { if planning.hasAccess { refresh() } }
    }
    private func cleanTitle(_ title: String) -> String {
        title.hasPrefix("Study: ") ? String(title.dropFirst(7)) : title
    }
    private func groupHeader(id: String, title: String, count: Int, minutes: Int, completed: Int) -> some View {
        Button {
            if expandedGroups.contains(id) { expandedGroups.remove(id) } else { expandedGroups.insert(id) }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "book.closed").foregroundStyle(Color.pilot).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text("\(count) study blocks · \(minutes) min · \(completed) complete")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(completed)/\(count)").font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Color.pilot)
                Image(systemName: expandedGroups.contains(id) ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 11).padding(.vertical, 10)
                .background(Color.pilot.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(count) study blocks, \(completed) completed. Show individual sessions")
    }
    private func localRow(_ event: PlannerEvent, grouped: Bool) -> some View {
        HStack(spacing: 12) {
            let tracked = PlannedStudyBlock.taskID(in: event.details) != nil
            if tracked {
                Toggle("Complete \(event.title)", isOn: Binding(get: { StudyBlockTracking.read(event.details).completedAt != nil }, set: { done in
                    do { try planning.setCompleted(done, local: event, context: context) } catch { app.error = error.localizedDescription }
                })).labelsHidden().toggleStyle(.checkbox)
            } else { Image(systemName: event.kind == "Exam" ? "graduationcap" : "calendar").foregroundStyle(Color.pilot) }
            VStack(alignment: .leading, spacing: 3) {
                if !grouped { Text(cleanTitle(event.title)).font(.system(size: 13, weight: .medium)).strikethrough(StudyBlockTracking.read(event.details).completedAt != nil) }
                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) · \(event.durationMinutes) min")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let id = PlannedStudyBlock.taskID(in: event.details) { FinishStudyTaskButton(taskID: id, title: event.title) }
            Menu {
                Button("Edit event") { editingEvent = event }
                Button("Focus on this event") { if focus.state == nil { focus.start(minutes: min(60, max(5, event.durationMinutes)), subjectID: event.subjectID) }; app.section = .focus }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).foregroundStyle(.secondary).accessibilityLabel("Actions for \(event.title)")
        }.padding(.vertical, 5)
    }
    private func externalRow(_ event: CalendarPlanningEvent, grouped: Bool) -> some View {
        HStack(spacing: 12) {
            if event.ownTaskID != nil {
                Toggle("Complete \(event.title)", isOn: Binding(get: { StudyBlockTracking.read(event.notes).completedAt != nil }, set: { done in
                    do { try planning.setCompleted(done, external: event) } catch { app.error = error.localizedDescription }
                })).labelsHidden().toggleStyle(.checkbox)
            } else { Image(systemName: "calendar").foregroundStyle(Color.pilot) }
            VStack(alignment: .leading, spacing: 3) {
                if !grouped { Text(cleanTitle(event.title)).font(.system(size: 13, weight: .medium)) }
                Text("\(event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened)) · \(planning.calendars.first { $0.id == event.calendarID }?.title ?? "Synced calendar")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let id = event.ownTaskID { FinishStudyTaskButton(taskID: id, title: event.title) }
            Menu { Button("Ask about this event") { app.ask("Help me with the calendar event \(event.title) on \(event.start.formatted(date: .abbreviated, time: .shortened)).") } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).foregroundStyle(.secondary).accessibilityLabel("Actions for \(event.title)")
        }.padding(.vertical, 5)
    }
    private func refresh() { do { try planning.refresh(); refreshError = nil } catch { refreshError = error.localizedDescription } }
}

private struct LocalAgendaGroup: Identifiable {
    let id: String
    let events: [PlannerEvent]
}

private struct ExternalAgendaGroup: Identifiable {
    let id: String
    let events: [CalendarPlanningEvent]
}
