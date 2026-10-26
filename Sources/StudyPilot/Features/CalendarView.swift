import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct PlannerCalendarView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(CalendarPlanningService.self) private var planning
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery(sort: \PlannerEvent.startDate) private var events: [PlannerEvent]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var selected = Date()
    @State private var mode = "Month"
    @State private var adding = false
    @State private var editingEvent: PlannerEvent?
    @State private var editingTask: Assignment?
    @State private var synced: [CalendarPlanningEvent] = []
    @State private var syncError: String?
    @State private var syncedAt: Date?
    @State private var deleting: PlannerEvent?
    private let calendar = Calendar.current
    private var days: [Date] {
        if mode == "Week" {
            let start = calendar.dateInterval(of: .weekOfYear, for: selected)!.start
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
        let month = calendar.dateInterval(of: .month, for: selected)!
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: month.start)!
        let count = Int(ceil(Double(offset + calendar.range(of: .day, in: .month, for: selected)!.count) / 7)) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "See the bigger picture", title: "Calendar", subtitle: "Your local deadlines and events. Selected synced calendars are listed below for the chosen day.")
                HStack(spacing: 16) {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous \(mode.lowercased())")
                    Text(selected, format: .dateTime.month(.wide).year()).font(.title3.bold()).frame(minWidth: 180)
                    Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next \(mode.lowercased())")
                    Button("Today") { selected = Date() }
                    Spacer()
                    Button("Plan my study", systemImage: "sparkles") { app.showingStudyPlanner = true }
                    Picker("View", selection: $mode) { Text("Month").tag("Month"); Text("Week").tag("Week") }.pickerStyle(.segmented).frame(width: 160)
                    Button("Add event", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent)
                }
                DisclosureGroup("Study block checklist") { StudySessionsView() }.font(.headline)
                syncedDay
                VStack(spacing: 8) {
                    HStack {
                        ForEach(0..<7, id: \.self) { index in
                            Text(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(days, id: \.self) { day in dayCell(day) }
                    }
                }.pilotCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text(selected, format: .dateTime.weekday(.wide).month(.wide).day()).font(.title3.bold())
                    let tasks = assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: selected) }
                    let dayEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: selected) }
                    if tasks.isEmpty && dayEvents.isEmpty { EmptyState(symbol: "calendar.badge.plus", title: "Time for something good", message: "Add a study session or exam, or drag a deadline onto this day.") }
                    ForEach(tasks) { task in AssignmentRow(assignment: task, subject: subject(task.subjectID)) { editingTask = task } }
                    ForEach(dayEvents) { event in
                        HStack(spacing: 16) {
                            Image(systemName: event.kind == "Exam" ? "graduationcap" : "clock").foregroundStyle(subject(event.subjectID)?.color ?? .pilot).font(.title2)
                            VStack(alignment: .leading, spacing: 6) { Text(event.title).font(.headline); SubjectBadge(subject: subject(event.subjectID)) }
                            Spacer()
                            Text(event.startDate, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                            Text("\(event.durationMinutes) min").font(.caption).foregroundStyle(.secondary)
                            Button("Edit") { editingEvent = event }
                        }.padding(.vertical, 8).contextMenu {
                            Button("Delete event…", role: .destructive) { deleting = event }
                        }
                    }
                }.pilotCard()
            }.padding(30)
        }
        .onAppear { if let date = app.selectedCalendarDate { selected = date; app.selectedCalendarDate = nil }; refreshSynced() }
        .onChange(of: selected) { refreshSynced() }
        .onChange(of: app.selectedCalendarDate) { if let date = app.selectedCalendarDate { selected = date; app.selectedCalendarDate = nil } }
        .sheet(isPresented: $adding) { EventEditor(date: selected) }
        .sheet(item: $editingEvent) { EventEditor(event: $0) }
        .sheet(item: $editingTask) { AssignmentEditor(assignment: $0) }
        .alert("Delete this event?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { context.delete(deleting); app.save(context) }; deleting = nil }
        } message: { Text("The event and its reminder will be removed.") }
    }
    private var syncedDay: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Synced calendars · \(selected.formatted(date: .abbreviated, time: .omitted))").font(.headline); Spacer(); Button("Refresh") { refreshSynced() }.disabled(!planning.hasAccess) }
            if !planning.hasAccess {
                Text("Connect calendars to see Google events here.").foregroundStyle(.secondary)
                Button("Connect calendars") { app.showingStudyPlanner = true }
            } else if synced.isEmpty { Text("No events from your selected synced calendars on this day.").foregroundStyle(.secondary) }
            ForEach(synced.prefix(100)) { event in
                HStack {
                    Image(systemName: "calendar").foregroundStyle(Color.pilot)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.callout.bold())
                        Text("\(event.allDay ? "All day" : event.start.formatted(date: .abbreviated, time: .shortened)) · \(planning.calendars.first { $0.id == event.calendarID }?.title ?? "Calendar")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Ask AI") { app.ask("Help me with the calendar event \(event.title) on \(event.start.formatted(date: .abbreviated, time: .shortened)).") }
                }.padding(.vertical, 4)
            }
            if let syncedAt { Text("Read from this Mac at \(syncedAt.formatted(date: .omitted, time: .shortened)). Google changes follow macOS Calendar sync.").font(.caption).foregroundStyle(.secondary) }
            if let syncError { Text(syncError).font(.caption).foregroundStyle(.red) }
        }.pilotCard()
    }
    private func refreshSynced() {
        guard planning.hasAccess else { synced = []; return }
        let start = calendar.startOfDay(for: selected), end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selected))!
        do { synced = try planning.chatEvents(in: DateInterval(start: start, end: end)); syncedAt = Date(); syncError = nil }
        catch { syncError = error.localizedDescription; synced = [] }
    }
    private func subject(_ id: UUID?) -> Subject? { subjects.first { $0.id == id } }
    private func move(_ value: Int) { selected = calendar.date(byAdding: mode == "Month" ? .month : .weekOfYear, value: value, to: selected) ?? selected }
    private func dayCell(_ day: Date) -> some View {
        let tasks = assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
        let dayEvents = events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
        let selectedDay = calendar.isDate(day, inSameDayAs: selected)
        return CalendarDayCell(day: day, tasks: tasks, events: dayEvents, subjects: subjects, selected: selectedDay, isWeek: mode == "Week", isCurrentMonth: calendar.isDate(day, equalTo: selected, toGranularity: .month))
            .onTapGesture { selected = day }
            .accessibilityAction { selected = day }
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
