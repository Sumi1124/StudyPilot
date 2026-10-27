import SwiftUI
import SwiftData
import AppKit
import StudyPilotCore
import StudyPilotData

struct StudyPlanningView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Environment(CalendarPlanningService.self) private var service
    @State private var tasks: [PlanningTask] = []
    @State private var plan: StudyPlan?
    @State private var previewAssignments: [AssignmentRecord] = []
    @State private var previewEvents: [PlannerEventRecord] = []
    @State private var generatedTasks: [PlanningTask] = []
    @State private var configured = false
    @State private var step = 0
    @State private var search = ""
    @State private var showCalendars = false
    @State private var saveToCalendar = false
    @State private var savedFirstDate: Date?
    @State private var savedMessage: String?
    private let stepNames = ["Assignments", "Study time", "Review"]
    private var selectedTasks: [PlanningTask] { tasks.filter(\.selected) }
    private var selectedMinutes: Int { selectedTasks.reduce(0) { $0 + $1.minutes } }
    private var visibleIDs: Set<String> {
        Set(tasks.filter { search.isEmpty || $0.title.localizedStandardContains(search) }.map(\.id))
    }
    private var hoursIssue: String? {
        let p = service.settings.preferences
        if p.weekdays.isEmpty { return "Choose at least one study day." }
        if p.startMinute >= p.endMinute { return "Your finish time must be later than your start time." }
        return nil
    }
    private var estimateIssue: String? {
        selectedTasks.contains { !(5...2400).contains($0.minutes) } ? "Enter between 5 and 2,400 remaining minutes for each selected assignment." : nil
    }
    private var busy: Bool { service.working }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("planner-top")
                        if let savedMessage { success(savedMessage) }
                        else {
                            switch step {
                            case 0: assignmentStep
                            case 1: timeStep
                            default: reviewStep
                            }
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 24)
                }
                .onChange(of: step) { proxy.scrollTo("planner-top", anchor: .top) }
                .onChange(of: savedMessage) { proxy.scrollTo("planner-top", anchor: .top) }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 780, idealWidth: 920, maxWidth: 1040, minHeight: 600, idealHeight: 760)
        .task {
            guard !configured else { return }; configured = true
            if let folder = context.container.configurations.first?.url.deletingLastPathComponent() { service.configure(folder: folder) }
            saveToCalendar = !service.settings.destinationID.isEmpty
            if service.hasAccess { refresh(); showCalendars = service.settings.deadlineCalendarIDs.isEmpty } else { rebuildTasks() }
        }
        .onChange(of: service.calendarRevision) { if configured { rebuildTasks(); plan = nil } }
        .onChange(of: assignments.map(\.record)) { _, _ in if configured { rebuildTasks(); plan = nil } }
        .onChange(of: tasks) { _, new in if new != generatedTasks { plan = nil }; service.status = nil }
        .onChange(of: service.settings.preferences) { old, new in
            plan = nil
            if old.days != new.days && service.hasAccess { service.needsRefresh = true }
        }
        .onChange(of: service.settings.deadlineCalendarIDs) { _, _ in refreshSources() }
        .onChange(of: service.settings.busyCalendarIDs) { _, _ in plan = nil }
        .onChange(of: service.settings.destinationID) { _, _ in plan = nil }
        .interactiveDismissDisabled(busy)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Plan my study", systemImage: "calendar.badge.clock").font(.title2.bold())
                    Text("Make room for your work, one step at a time.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { persist(); dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
            }
            HStack(spacing: 12) {
                ForEach(0..<3) { index in
                    Button { step = index; service.error = nil } label: {
                        HStack(spacing: 8) {
                            Image(systemName: step > index ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                            Text(stepNames[index]).fontWeight(step == index ? .semibold : .regular)
                            Spacer(minLength: 0)
                        }.padding(12).frame(maxWidth: .infinity)
                            .foregroundStyle(step == index ? Color.pilot : Color.secondary)
                            .background(step == index ? Color.pilot.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(busy || savedMessage != nil)
                        .accessibilityLabel("Step \(index + 1): \(stepNames[index])")
                        .accessibilityAddTraits(step == index ? .isSelected : [])
                        .accessibilityRemoveTraits(step == index ? [] : .isSelected)
                }
            }
        }.padding(22)
    }
    private var assignmentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("What do you need to work on?", detail: "Select assignments and check how much work is left.")
            connectionSection
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Find an assignment", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    Spacer()
                    Button("Select shown") { for i in tasks.indices where visibleIDs.contains(tasks[i].id) { tasks[i].selected = true } }.disabled(visibleIDs.isEmpty)
                    Button("Clear shown") { for i in tasks.indices where visibleIDs.contains(tasks[i].id) { tasks[i].selected = false } }.disabled(visibleIDs.isEmpty)
                }
                if tasks.isEmpty {
                    ContentUnavailableView("No assignments yet", systemImage: "checklist", description: Text("Add an assignment in StudyPilot, or choose a calendar containing your deadlines above."))
                } else if visibleIDs.isEmpty { Text("No assignments match your search.").foregroundStyle(.secondary).padding(.vertical, 24) }
                ForEach($tasks) { $task in
                    if visibleIDs.contains(task.id) { taskRow($task) }
                }
                Text("Remaining time includes future study blocks you already booked. The preview deducts that booked time to avoid adding it twice.").font(.caption).foregroundStyle(.secondary)
                if let estimateIssue { Label(estimateIssue, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange) }
            }.pilotCard()
        }
    }
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: service.hasAccess ? "calendar.badge.checkmark" : "calendar.badge.plus").font(.title2).foregroundStyle(Color.pilot)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.hasAccess ? "Calendars connected" : "Bring in your Google deadlines").font(.headline)
                    Text(service.hasAccess ? "\(service.settings.deadlineCalendarIDs.count) assignment calendars · \(service.settings.busyCalendarIDs.count) checked for conflicts" : "Optional. You can also plan your saved StudyPilot assignments.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if service.hasAccess {
                    Button("Refresh", systemImage: "arrow.clockwise") { refresh() }.disabled(busy)
                } else {
                    Button("Connect calendars") { Task { await service.connect(); rebuildTasks(); showCalendars = service.hasAccess } }.disabled(busy)
                }
            }
            DisclosureGroup(service.hasAccess ? "Choose calendars" : "Google Calendar setup", isExpanded: $showCalendars) {
                VStack(alignment: .leading, spacing: 16) {
                    if service.hasAccess { calendarChoices }
                    else {
                        Text("Add your Google account in Apple Calendar and enable Calendars. Then return here and connect.").font(.callout).foregroundStyle(.secondary)
                        Button("Open Apple Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
                    }
                    Text("Google updates arrive through Apple Calendar. If a deadline is missing, refresh Apple Calendar first, then refresh here.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
            if let date = service.lastRefresh { Text("Last read at \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
        }.pilotCard()
    }
    private var calendarChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calendar").frame(maxWidth: .infinity, alignment: .leading)
                Text("Find assignments").frame(width: 135)
                Text("Avoid conflicts").frame(width: 125)
            }.font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(service.calendars) { calendar in
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text(calendar.title); Text(calendar.account).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Find assignments in \(calendar.title)", isOn: membership(calendar.id, keyPath: \.deadlineCalendarIDs)).labelsHidden().toggleStyle(.checkbox).frame(width: 135)
                    Toggle("Avoid conflicts in \(calendar.title)", isOn: membership(calendar.id, keyPath: \.busyCalendarIDs)).labelsHidden().toggleStyle(.checkbox).frame(width: 125)
                }.padding(.vertical, 3)
            }
            if service.calendars.isEmpty { Text("No calendars found. Add your Google account in Apple Calendar, let it sync, then refresh.").foregroundStyle(.secondary) }
            Text("Find assignments lists events as possible deadlines; you choose which ones are homework. Avoid conflicts protects classes and other commitments. Selected deadlines don't occupy study time.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func taskRow(_ binding: Binding<PlanningTask>) -> some View {
        let task = binding.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: binding.selected) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.headline)
                        Text("\(task.id.hasPrefix("calendar:") ? "Calendar deadline" : "StudyPilot assignment") · \(task.deadline.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if task.deadline <= Date() { Label("Past due", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                }
            }.toggleStyle(.checkbox)
            if task.selected {
                HStack(spacing: 12) {
                    Text("Time left").font(.callout)
                    TextField("Minutes", value: binding.minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 75).accessibilityLabel("Remaining minutes for \(task.title)")
                    Text("min").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Priority", selection: binding.priority) { Text("Low").tag(0); Text("Normal").tag(1); Text("High").tag(2) }.frame(width: 160)
                }.padding(.leading, 22)

            }
        }.padding(14).background(task.selected ? Color.pilot.opacity(0.055) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
    private var timeStep: some View {
        @Bindable var service = service
        return VStack(alignment: .leading, spacing: 18) {
            sectionTitle("When do you like to study?", detail: "We'll fit sessions inside these hours and around your calendar.")
            StudyRoutinesView()
            VStack(alignment: .leading, spacing: 18) {
                Picker("Plan ahead", selection: $service.settings.preferences.days) { Text("7 days").tag(7); Text("14 days").tag(14); Text("28 days").tag(28) }.frame(width: 240)
                Divider()
                Text("Study days").font(.headline)
                HStack(spacing: 10) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = (Calendar.current.firstWeekday - 1 + offset) % 7 + 1
                        Button { if service.settings.preferences.weekdays.contains(day) { service.settings.preferences.weekdays.remove(day) } else { service.settings.preferences.weekdays.insert(day) } } label: {
                            Text(Calendar.current.shortWeekdaySymbols[day - 1]).font(.callout.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(service.settings.preferences.weekdays.contains(day) ? Color.pilot.opacity(0.16) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(service.settings.preferences.weekdays.contains(day) ? Color.pilot : Color.secondary)
                        }.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day - 1]).accessibilityValue(service.settings.preferences.weekdays.contains(day) ? "Selected" : "Not selected")
                    }
                }
                HStack(spacing: 32) {
                    DatePicker("Start", selection: clockBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Finish", selection: clockBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    Spacer()
                }
                Text("Same hours on each selected day · \(TimeZone.current.identifier)").font(.caption).foregroundStyle(.secondary)
                if let hoursIssue { Label(hoursIssue, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            }.pilotCard()
            VStack(alignment: .leading, spacing: 18) {
                Text("A manageable pace").font(.headline)
                HStack(spacing: 32) {
                    Picker("Session", selection: $service.settings.preferences.sessionMinutes) { Text("25 min").tag(25); Text("50 min").tag(50); Text("60 min").tag(60) }.frame(width: 205)
                    Stepper("Break: \(service.settings.preferences.breakMinutes) min", value: $service.settings.preferences.breakMinutes, in: 0...30, step: 5)
                    Spacer()
                }
                Stepper("Daily study limit: \(service.settings.preferences.dailyMinutes) min", value: $service.settings.preferences.dailyMinutes, in: 30...480, step: 30).frame(maxWidth: 330)
            }.pilotCard()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Reschedule sessions I don't finish", isOn: Binding(get: { service.automaticallyReschedules }, set: { service.settings.autoReschedule = $0; persist() }))
                Text("After a session ends, an unchecked study block moves to the next available time before its deadline. Checks run while the app is open and when reopened. Tick finished sessions in Calendar.").font(.caption).foregroundStyle(.secondary)
            }.pilotCard()
        }
    }
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Your study plan", detail: "Review the sessions, then choose where to save them.")
            if let plan {
                preview(plan)
            } else {
                ContentUnavailableView("Ready for a preview?", systemImage: "calendar.badge.clock", description: Text("Choose assignments and study hours first. Nothing is added until you save."))
                Button("Preview study plan") { generate() }.buttonStyle(.borderedProminent).disabled(selectedTasks.isEmpty || estimateIssue != nil || hoursIssue != nil || busy)
            }
            destinationSection
        }
    }
    private func preview(_ value: StudyPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 28) {
                metric("Sessions", value: "\(value.blocks.count)")
                metric("Study time", value: "\(value.blocks.reduce(0) { $0 + $1.minutes }) min")
                metric("Selected", value: "\(selectedTasks.count)")
                Spacer()
                Button("Adjust hours") { step = 1 }
            }
            if value.alreadyPlannedMinutes > 0 { Label("\(value.alreadyPlannedMinutes) min already booked; kept in your calendar.", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary) }
            if !value.unscheduled.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Some work still needs time", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                    ForEach(value.unscheduled) { item in Text("\(item.title) · \(item.minutes) min left. \(item.reason)").font(.callout) }
                    Text("Try more study days or a higher daily limit. Past deadlines must be changed at their source.").font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            let days = Array(Set(value.blocks.map { Calendar.current.startOfDay(for: $0.start) })).sorted()
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 12) {
                    Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.headline)
                    ForEach(value.blocks.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }) { block in
                        HStack(spacing: 16) {
                            Rectangle().fill(Color.pilot).frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(block.start.formatted(date: .omitted, time: .shortened)) – \(block.end.formatted(date: .omitted, time: .shortened))").font(.callout).monospacedDigit()
                                Text(block.title).fontWeight(.medium)
                            }
                            Spacer()
                            Text("\(block.minutes) min").font(.callout).foregroundStyle(.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            }
            if value.blocks.isEmpty && value.unscheduled.isEmpty { Label("All selected work already has study time scheduled.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        }.pilotCard()
    }
    private var destinationSection: some View {
        @Bindable var service = service
        return VStack(alignment: .leading, spacing: 12) {
            Text("Save your sessions").font(.headline)
            Picker("Save in", selection: $saveToCalendar) {
                Text("StudyPilot only").tag(false)
                Text("Synced calendar").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 360)
            if saveToCalendar {
                if service.hasAccess {
                    Picker("Calendar", selection: $service.settings.destinationID) {
                        Text("Choose a calendar…").tag("")
                        ForEach(service.calendars.filter(\.writable)) { Text($0.label).tag($0.id) }
                    }
                    Text("Choose a Google calendar to sync the sessions to Google. Changing this calendar requires a fresh preview so it can be checked for conflicts.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Connect calendars in Assignments to save sessions to Google.").font(.callout).foregroundStyle(.secondary)
                    Button("Set up calendars") { step = 0; showCalendars = true }
                }
            } else { Text("Sessions appear in your StudyPilot calendar. They won't be added to Google.").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
    private func success(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your study time is booked", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
            Text(message).foregroundStyle(.secondary)
            Text("Tick off each session in Calendar when you finish it.").font(.callout)
            HStack {
                Button("View calendar") { let date = savedFirstDate ?? Date(); app.openCalendar(date); dismiss() }.buttonStyle(.borderedProminent)
                Button("Plan more") { savedMessage = nil; step = 0; rebuildTasks() }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = service.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack(spacing: 16) {
                if busy { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(savedMessage == nil ? "\(selectedTasks.count) assignments selected · \(selectedMinutes) min left" : "Sessions saved").font(.callout.weight(.medium))
                    Text(savedMessage != nil ? "Your schedule is ready in Calendar." : (step == 2 && plan != nil ? "Only the previewed sessions will be added." : "Preview first. Save when you're happy with the plan.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if savedMessage == nil {
                    if step > 0 { Button("Back") { step -= 1 }.disabled(busy) }
                    if step == 0 {
                        Button("Study time", systemImage: "arrow.right") { service.error = nil; step = 1 }.buttonStyle(.borderedProminent).disabled(selectedTasks.isEmpty || estimateIssue != nil || busy)
                    } else if step == 1 || plan == nil {
                        Button("Preview plan", systemImage: "calendar.badge.clock") { generate() }.buttonStyle(.borderedProminent).disabled(selectedTasks.isEmpty || estimateIssue != nil || hoursIssue != nil || busy)
                    } else if let plan, !plan.blocks.isEmpty {
                        Button(saveToCalendar ? "Add sessions to calendar" : "Save in StudyPilot") { if saveToCalendar { publish(plan) } else { saveLocally(plan) } }.buttonStyle(.borderedProminent).disabled(busy || (saveToCalendar && (!service.hasAccess || service.settings.destinationID.isEmpty)))
                    }
                } else { Button("Done") { persist(); dismiss() }.buttonStyle(.borderedProminent) }
            }
        }.padding(20).background(.bar)
    }
    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.title2.bold()); Text(detail).font(.callout).foregroundStyle(.secondary) }.padding(.top, 8)
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(value).font(.title2.bold()).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    private func refreshSources() {
        plan = nil
        if service.hasAccess { refresh() } else { rebuildTasks() }
    }
    private func membership(_ id: String, keyPath: WritableKeyPath<CalendarPlanningSettings, Set<String>>) -> Binding<Bool> {
        Binding(get: { service.settings[keyPath: keyPath].contains(id) }, set: { selected in
            if selected { service.settings[keyPath: keyPath].insert(id) } else { service.settings[keyPath: keyPath].remove(id) }
        })
    }
    private func clockBinding(_ key: WritableKeyPath<PlanningPreferences, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: service.settings.preferences[keyPath: key] / 60, minute: service.settings.preferences[keyPath: key] % 60, second: 0, of: Date()) ?? Date() }, set: { date in
            service.settings.preferences[keyPath: key] = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        })
    }
    private func rebuildTasks() {
        let previous = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var candidates = service.taskCandidates()
        candidates += assignments.filter { !$0.isDone }.map { PlanningTask(id: "local:\($0.id.uuidString)", title: $0.title, details: $0.details, deadline: $0.dueDate, minutes: max(5, $0.estimatedMinutes), priority: $0.priority) }
        tasks = candidates.map { item in
            var item = item
            if let saved = previous[item.id] ?? service.settings.taskOverrides[item.id] { item.minutes = saved.minutes; item.priority = saved.priority; item.selected = saved.selected }
            item.steps = []
            return item
        }.sorted { $0.deadline < $1.deadline }
    }
    private func persist() { do { try service.saveSettings(tasks: tasks) } catch { service.error = error.localizedDescription } }
    private func refresh() {
        plan = nil; service.error = nil
        do { try service.refresh(); rebuildTasks() } catch { service.error = error.localizedDescription }
    }
    private func databaseSnapshot() throws -> ([AssignmentRecord], [PlannerEventRecord]) {
        (try context.fetch(FetchDescriptor<Assignment>()).map(\.record).sorted { $0.id.uuidString < $1.id.uuidString },
         try context.fetch(FetchDescriptor<PlannerEvent>()).map(\.record).sorted { $0.id.uuidString < $1.id.uuidString })
    }
    private func generate() {
        service.error = nil; service.status = nil; plan = nil
        do {
            try service.settings.preferences.validate()
            try service.saveSettings(tasks: tasks)
            if service.hasAccess { try service.refresh() }
            // Retain edits, but refresh source deadlines before producing a preview.
            rebuildTasks()
            let snapshot = try databaseSnapshot(); previewAssignments = snapshot.0; previewEvents = snapshot.1
            let selectedIDs = Set(tasks.filter(\.selected).map(\.id))
            let localBusy = snapshot.1.map { PlanningBusyTime(start: $0.startDate, end: $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)), taskID: PlannedStudyBlock.taskID(in: $0.details)) }
            let generated = try StudyPlanner.makePlan(tasks: tasks, busy: service.busyTimes(excludingTasks: selectedIDs) + localBusy,
                                                      preferences: service.settings.preferences, now: Date())
            generatedTasks = tasks; plan = generated; step = 2
        } catch { service.error = error.localizedDescription }
    }
    private func validate(_ value: StudyPlan) throws {
        let snapshot = try databaseSnapshot()
        guard snapshot.0 == previewAssignments && snapshot.1 == previewEvents else { throw PlanningError.invalid("Your StudyPilot workspace changed. Generate a fresh plan before saving.") }
        try service.validatePreview(value, tasks: tasks)
    }
    private func saveLocally(_ value: StudyPlan) {
        var inserted = false
        do {
            try validate(value)
            inserted = true
            for block in value.blocks {
                let task = previewAssignments.first { "local:\($0.id.uuidString)" == block.taskID }
                context.insert(PlannerEvent(PlannerEventRecord(id: block.id, title: "Study: \(block.title)", subjectID: task?.subjectID, startDate: block.start, durationMinutes: block.minutes, details: block.notes)))
            }
            try context.save(); savedFirstDate = value.blocks.first?.start; plan = nil; savedMessage = "Saved \(value.blocks.count) sessions in StudyPilot."
        } catch { if inserted { context.rollback() }; service.error = error.localizedDescription }
    }
    private func publish(_ value: StudyPlan) {
        do { try validate(value); try service.publish(value, tasks: tasks); savedFirstDate = value.blocks.first?.start; plan = nil; savedMessage = service.status ?? "Your sessions were added to the selected calendar." }
        catch { service.error = error.localizedDescription }
    }
}
