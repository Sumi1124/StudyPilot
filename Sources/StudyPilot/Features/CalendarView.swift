import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

private enum SchoolAgendaItem: Identifiable {
    case task(Assignment), local(PlannerEvent), synced(CalendarPlanningEvent)
    var id: String { switch self { case .task(let a): "task:\(a.id)"; case .local(let e): "local:\(e.id)"; case .synced(let e): e.id } }
    var start: Date { switch self { case .task(let a): a.dueDate; case .local(let e): e.startDate; case .synced(let e): e.start } }
    var isAllDay: Bool { if case .synced(let e) = self { return e.allDay }; return false }
}
struct PlannerCalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(CalendarPlanningService.self) private var planning
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery(sort: \PlannerEvent.startDate) private var events: [PlannerEvent]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var selected = Date()
    @AppStorage("calendarViewMode") private var mode = "Agenda"
    @AppStorage("calendarHideCompleted") private var hideCompleted = true
    @State private var search = ""
    @State private var adding = false
    @State private var editingEvent: PlannerEvent?
    @State private var editingTask: Assignment?
    @State private var synced: [CalendarPlanningEvent] = []
    @State private var syncError: String?
    @State private var syncedAt: Date?
    @State private var deleting: PlannerEvent?
    private let calendar = Calendar.current
    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: selected)!.start }
    private var weekDays: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var agendaDays: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: selected)) } }
    private var readRange: DateInterval {
        let start = mode == "Week" ? weekStart : calendar.startOfDay(for: selected)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: mode == "Month" ? 1 : 7, to: start)!)
    }
    private var days: [Date] {
        if mode == "Week" { return weekDays }
        let month = calendar.dateInterval(of: .month, for: selected)!
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: month.start)!
        let count = Int(ceil(Double(offset + calendar.range(of: .day, in: .month, for: selected)!.count) / 7)) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        VStack(spacing: 0) {
            navigation
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("calendar-top")
                        if mode == "Agenda" {
                            weekSummary
                            ForEach(agendaDays, id: \.self) { day in agendaDay(day) }
                        } else {
                            grid
                            agendaDay(selected)
                        }
                        DisclosureGroup("Study block checklist") { StudySessionsView() }.font(.headline)
                    }.padding(.horizontal, 26).padding(.bottom, 26)
                }
                .onChange(of: selected) { if mode == "Agenda" { proxy.scrollTo("calendar-top", anchor: .top) } }
                .onChange(of: mode) { proxy.scrollTo("calendar-top", anchor: .top) }
            }
        }
        .onAppear { if let date = app.selectedCalendarDate { selected = date; app.selectedCalendarDate = nil }; refreshSynced() }
        .onChange(of: selected) { refreshSynced() }
        .onChange(of: mode) { refreshSynced() }
        .onChange(of: planning.calendarRevision) { refreshSynced() }
        .onChange(of: app.selectedCalendarDate) { if let date = app.selectedCalendarDate { selected = date; app.selectedCalendarDate = nil } }
        .sheet(isPresented: $adding) { EventEditor(date: selected) }
        .sheet(item: $editingEvent) { EventEditor(event: $0) }
        .sheet(item: $editingTask) { AssignmentEditor(assignment: $0) }
        .alert("Delete this event?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { context.delete(deleting); app.save(context) }; deleting = nil }
        } message: { Text("The event and its reminder will be removed.") }
    }
    private var navigation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Your deadlines and time to work, together.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Plan my study", systemImage: "calendar.badge.clock") { app.showingStudyPlanner = true }.buttonStyle(.borderedProminent)
                Button("Add event", systemImage: "plus") { adding = true }
            }
            HStack(spacing: 10) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }.help(mode == "Month" ? "Previous month" : "Previous week")
                DatePicker("Selected date", selection: $selected, displayedComponents: .date).labelsHidden().frame(width: 140)
                Button { move(1) } label: { Image(systemName: "chevron.right") }.help(mode == "Month" ? "Next month" : "Next week")
                Button("Today") { selected = Date() }
                Spacer()
                Picker("View", selection: $mode) { Text("Agenda").tag("Agenda"); Text("Week").tag("Week"); Text("Month").tag("Month") }.pickerStyle(.segmented).labelsHidden().frame(width: 245)
            }
            HStack(spacing: 16) {
                TextField("Find a deadline or event", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Toggle("Hide completed", isOn: $hideCompleted).toggleStyle(.checkbox)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refreshSynced() }.disabled(!planning.hasAccess)
            }
            HStack(spacing: 8) {
                Image(systemName: planning.hasAccess ? "checkmark.circle" : "calendar")
                Text(planning.hasAccess ? "Selected synced calendars + StudyPilot\(syncedAt.map { " · read at " + $0.formatted(date: .omitted, time: .shortened) } ?? "")" : "StudyPilot events only")
                if !planning.hasAccess { Button("Connect calendars") { app.showingStudyPlanner = true }.buttonStyle(.link) }
            }.font(.caption).foregroundStyle(.secondary)
            if let syncError { Text(syncError).font(.caption).foregroundStyle(.red) }
            if let message = planning.completionCleanupMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        }.padding(22).background(.bar)
    }
    private var weekSummary: some View {
        let tasks = assignments.filter { taskVisible($0) && $0.dueDate >= readRange.start && $0.dueDate < readRange.end }
        let local = events.filter { localVisible($0) && $0.startDate < readRange.end && $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)) > readRange.start }
        let external = synced.filter { externalVisible($0) && $0.start < readRange.end && ($0.end > readRange.start || ($0.start == $0.end && $0.start >= readRange.start)) }
        let sessions = local.count + external.count
        let minutes = local.reduce(0) { $0 + max(0, Int(min(readRange.end, $1.startDate.addingTimeInterval(Double($1.durationMinutes * 60))).timeIntervalSince(max(readRange.start, $1.startDate)) / 60)) }
            + external.filter { !$0.allDay }.reduce(0) { $0 + max(0, Int(min(readRange.end, $1.end).timeIntervalSince(max(readRange.start, $1.start)) / 60)) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack { Text("\(readRange.start.formatted(.dateTime.month(.abbreviated).day())) – \(agendaDays.last!.formatted(.dateTime.month(.abbreviated).day()))").font(.headline); Spacer(); Text("This view follows your search and completed filter.").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 30) {
                statistic("Local deadlines", value: "\(tasks.count)", symbol: "flag")
                statistic("Calendar events", value: "\(sessions)", symbol: "calendar")
                statistic("Timed events", value: "\(minutes) min", symbol: "clock")
                Spacer()
            }
            Text("Calendar events include classes and commitments. Deadlines are not booked study time. Google updates follow macOS Calendar sync.").font(.caption).foregroundStyle(.secondary)
        }.pilotCard()
    }
    private func statistic(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold()).monospacedDigit() }
    }
    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selected, format: .dateTime.month(.wide).year()).font(.headline)
            Text("Grid: StudyPilot items. Synced events are included in the agenda below.").font(.caption).foregroundStyle(.secondary)
            HStack { ForEach(0..<7, id: \.self) { index in Text(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) { ForEach(days, id: \.self) { day in dayCell(day) } }
        }.pilotCard()
    }
    private func agendaDay(_ day: Date) -> some View {
        let entries = items(on: day)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(spacing: 1) { Text(day, format: .dateTime.weekday(.abbreviated)).font(.caption.weight(.semibold)); Text(day, format: .dateTime.day()).font(.title2.bold()) }
                    .foregroundStyle(calendar.isDateInToday(day) ? Color.pilot : Color.primary).frame(width: 58, height: 60).background(Color.pilot.opacity(calendar.isDateInToday(day) ? 0.13 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) { Text(calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide))).font(.headline); Text(day, format: .dateTime.month(.wide).day()).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("\(entries.count) item\(entries.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Button("Add event") { selected = day; adding = true }.font(.caption)
            }
            if entries.isEmpty { Text(search.isEmpty ? "No matching deadlines or events. Room to plan something." : "No matches on this day.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8) }
            ForEach(entries) { entry in
                switch entry {
                case .task(let task):
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ASSIGNMENT DEADLINE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        AssignmentRow(assignment: task, subject: subject(task.subjectID)) { editingTask = task }
                    }
                case .local(let event): localRow(event)
                case .synced(let event): externalRow(event)
                }
                if entry.id != entries.last?.id { Divider() }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
    private func localRow(_ event: PlannerEvent) -> some View {
        HStack(spacing: 14) {
            Toggle("Complete \(event.title)", isOn: Binding(get: { StudyBlockTracking.read(event.details).completedAt != nil }, set: { done in do { try planning.setCompleted(done, local: event, context: context) } catch { app.error = error.localizedDescription } })).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.callout.weight(.semibold)).strikethrough(StudyBlockTracking.read(event.details).completedAt != nil)
                Text(localTimeLabel(event)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let id = PlannedStudyBlock.taskID(in: event.details) { FinishStudyTaskButton(taskID: id, title: event.title) }
            Button("Edit") { editingEvent = event }
        }.padding(.vertical, 8).contextMenu { Button("Delete event…", role: .destructive) { deleting = event } }
    }
    private func localTimeLabel(_ event: PlannerEvent) -> String {
        let end = event.startDate.addingTimeInterval(Double(event.durationMinutes * 60))
        let endLabel = end.formatted(date: calendar.isDate(event.startDate, inSameDayAs: end) ? .omitted : .abbreviated, time: .shortened)
        return "\(event.startDate.formatted(date: .abbreviated, time: .shortened)) – \(endLabel) · \(event.durationMinutes) min · StudyPilot"
    }
    private func externalRow(_ event: CalendarPlanningEvent) -> some View {
        HStack(spacing: 14) {
            if event.ownTaskID != nil {
                Toggle("Complete \(event.title)", isOn: Binding(get: { StudyBlockTracking.read(event.notes).completedAt != nil }, set: { done in do { try planning.setCompleted(done, external: event); refreshSynced() } catch { app.error = error.localizedDescription } })).labelsHidden().toggleStyle(.checkbox).disabled(!event.writable || event.recurring)
            } else { Image(systemName: "calendar").foregroundStyle(Color.pilot).frame(width: 16) }
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.callout.weight(.semibold)).strikethrough(StudyBlockTracking.read(event.notes).completedAt != nil || planning.isTaskFinished(event.id))
                Text("\(event.allDay ? "All day" : event.start.formatted(date: .abbreviated, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)) · \(planning.calendars.first { $0.id == event.calendarID }?.title ?? "Synced calendar")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let id = event.ownTaskID { FinishStudyTaskButton(taskID: id, title: event.title) }
            else if planning.settings.deadlineCalendarIDs.contains(event.calendarID) { FinishStudyTaskButton(taskID: event.id, title: event.title) }
            Menu { Button("Ask AI about this event") { app.ask("Help me with the calendar event \(event.title) on \(event.start.formatted(date: .abbreviated, time: .shortened)).") } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel("Options for \(event.title)")
        }.padding(.vertical, 8)
    }
    private func matches(_ title: String, subjectID: UUID? = nil) -> Bool { search.isEmpty || "\(title) \(subject(subjectID)?.name ?? "")".localizedStandardContains(search) }
    private func taskVisible(_ task: Assignment) -> Bool { (!hideCompleted || !task.isDone) && matches(task.title, subjectID: task.subjectID) }
    private func localVisible(_ event: PlannerEvent) -> Bool { !planning.isTaskFinished(PlannedStudyBlock.taskID(in: event.details)) && (!hideCompleted || StudyBlockTracking.read(event.details).completedAt == nil) && matches(event.title, subjectID: event.subjectID) }
    private func externalVisible(_ event: CalendarPlanningEvent) -> Bool { !planning.isTaskFinished(event.ownTaskID) && (!hideCompleted || (StudyBlockTracking.read(event.notes).completedAt == nil && !planning.isTaskFinished(event.id))) && matches(event.title) }
    private func items(on day: Date) -> [SchoolAgendaItem] {
        var result = assignments.filter { taskVisible($0) && calendar.isDate($0.dueDate, inSameDayAs: day) }.map(SchoolAgendaItem.task)
        result += events.filter { localVisible($0) && SchoolAgenda.occurs(start: $0.startDate, end: $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)), on: day) }.map(SchoolAgendaItem.local)
        result += synced.filter { externalVisible($0) && SchoolAgenda.occurs(start: $0.start, end: $0.end, on: day) }.map(SchoolAgendaItem.synced)
        return result.sorted { a, b in if a.isAllDay != b.isAllDay { return a.isAllDay }; return a.start == b.start ? a.id < b.id : a.start < b.start }
    }
    private func refreshSynced() {
        guard planning.hasAccess else { synced = []; syncError = nil; syncedAt = nil; return }
        do { synced = try planning.chatEvents(in: readRange); syncedAt = Date(); syncError = nil }
        catch { syncError = error.localizedDescription; synced = []; syncedAt = nil }
    }
    private func subject(_ id: UUID?) -> Subject? { subjects.first { $0.id == id } }
    private func move(_ value: Int) { selected = calendar.date(byAdding: mode == "Month" ? .month : .weekOfYear, value: value, to: selected) ?? selected }
    private func dayCell(_ day: Date) -> some View {
        let tasks = assignments.filter { taskVisible($0) && calendar.isDate($0.dueDate, inSameDayAs: day) }
        let dayEvents = events.filter { localVisible($0) && calendar.isDate($0.startDate, inSameDayAs: day) }
        return CalendarDayCell(day: day, tasks: tasks, events: dayEvents, subjects: subjects, selected: calendar.isDate(day, inSameDayAs: selected), isWeek: mode == "Week", isCurrentMonth: calendar.isDate(day, equalTo: selected, toGranularity: .month))
            .onTapGesture { selected = day }.accessibilityAction { selected = day }
            .dropDestination(for: String.self) { items, _ in
                guard let value = items.first else { return false }
                let parts = value.split(separator: ":"); guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return false }
                if parts[0] == "assignment", let task = assignments.first(where: { $0.id == id }) { task.apply(PlannerLogic.reschedule(task.record, to: day)) }
                else if parts[0] == "event", let event = events.first(where: { $0.id == id }) {
                    let time = calendar.dateComponents([.hour, .minute], from: event.startDate)
                    let date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
                    if let reminder = event.reminderDate { event.reminderDate = reminder.addingTimeInterval(date.timeIntervalSince(event.startDate)) }
                    event.startDate = date
                } else { return false }
                selected = day; return app.save(context)
            }
    }
}
struct CalendarDayCell: View {
    @Environment(AppState.self) private var app
    let day: Date
    let tasks: [Assignment]
    let events: [PlannerEvent]
    let subjects: [Subject]
    let selected: Bool
    let isWeek: Bool
    let isCurrentMonth: Bool
    private var extra: Int { tasks.count + events.count - min(tasks.count, 2) - min(events.count, 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(day, format: .dateTime.day()).font(.system(size: 12, weight: .semibold)).foregroundStyle(Calendar.current.isDateInToday(day) ? Color.pilot : Color.primary)
                Spacer()
                if Calendar.current.isDateInToday(day) { Circle().fill(Color.pilot).frame(width: 5, height: 5) }
            }.padding(.bottom, 4)
            ForEach(tasks.prefix(isWeek ? 8 : 2)) { task in taskLabel(task) }
            ForEach(events.prefix(isWeek ? 8 : 1)) { event in
                Label(event.title, systemImage: event.kind == "Exam" ? "graduationcap" : "clock")
                    .font(.system(size: 10)).lineLimit(1).padding(3)
                    .foregroundStyle(subjects.first { $0.id == event.subjectID }?.color ?? Color.pilot)
                    .draggable("event:\(event.id.uuidString)")
            }
            if !isWeek && extra > 0 { Text("+\(extra) more").font(.system(size: 9)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(9).frame(maxWidth: .infinity, minHeight: isWeek ? 240 : 105, alignment: .topLeading)
            .background(selected ? Color.pilot.opacity(0.07) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.pilot.opacity(0.65) : Color.clear, lineWidth: 1))
            .opacity(!isWeek && !isCurrentMonth ? 0.45 : 1)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(.isButton)
    }
    private func taskLabel(_ task: Assignment) -> some View {
        let color = PlannerLogic.isOverdue(task.record, at: app.now) ? Color.red : (subjects.first { $0.id == task.subjectID }?.color ?? Color.pilot)
        return Text(task.title).font(.system(size: 10, weight: .medium)).lineLimit(1).strikethrough(task.isDone)
            .frame(maxWidth: .infinity, alignment: .leading).padding(4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .draggable("assignment:\(task.id.uuidString)").help("\(task.title) — drag to reschedule")
    }
}
struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    let event: PlannerEvent?
    @State private var draft: PlannerEventRecord
    @State private var remind: Bool
    @State private var error: String?
    init(event: PlannerEvent? = nil, date: Date = Date()) {
        self.event = event
        _draft = State(initialValue: event?.record ?? PlannerEventRecord(startDate: date))
        _remind = State(initialValue: event?.reminderDate != nil)
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(event == nil ? "Plan something" : "Edit event").font(.title2.bold()).padding(24)
            Form {
                TextField("Title", text: $draft.title)
                Picker("Type", selection: $draft.kind) { Text("Study session").tag("Study"); Text("Examination").tag("Exam") }
                SubjectPicker(subjects: subjects, selection: $draft.subjectID)
                DatePicker("Starts", selection: $draft.startDate)
                Stepper("Duration: \(draft.durationMinutes) minutes", value: $draft.durationMinutes, in: 5...720, step: 5)
                TextField("Details", text: $draft.details, axis: .vertical).lineLimit(2...4)
                Toggle("Remind me", isOn: $remind)
                if remind { DatePicker("Reminder", selection: Binding(get: { draft.reminderDate ?? draft.startDate.addingTimeInterval(-900) }, set: { draft.reminderDate = $0 })) }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
            SheetActions(title: "Save event", disabled: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }) {
                draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.reminderDate = remind ? (draft.reminderDate ?? draft.startDate.addingTimeInterval(-900)) : nil
                if let date = draft.reminderDate, (date <= Date() && date != event?.reminderDate) || date >= draft.startDate { error = "Choose a future reminder before the event starts."; return }
                if let event { event.apply(draft) } else { context.insert(PlannerEvent(draft)) }
                if app.save(context) { dismiss() }
            }
        }.frame(width: 550, height: 570)
    }
}
