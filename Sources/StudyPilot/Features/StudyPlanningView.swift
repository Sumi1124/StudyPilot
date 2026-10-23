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
    @LiveQuery(sort: \PlannerEvent.startDate) private var localEvents: [PlannerEvent]
    @Environment(CalendarPlanningService.self) private var service
    @State private var tasks: [PlanningTask] = []
    @State private var plan: StudyPlan?
    @State private var aiTaskID: String?
    @State private var aiRequest: Task<Void, Never>?
    @State private var aiRequestID: UUID?
    @State private var previewAssignments: [AssignmentRecord] = []
    @State private var previewEvents: [PlannerEventRecord] = []
    @State private var generatedTasks: [PlanningTask] = []
    @State private var configured = false

    var body: some View {
        @Bindable var service = service
        VStack(spacing: 0) {
            HStack {
                Label("Plan my study", systemImage: "sparkles").font(.title2.bold())
                Spacer()
                Button("Done") { persist(); dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Turn your deadlines into time to work.").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Choose assignments, estimate the work, and preview a schedule around your classes and other commitments.").foregroundStyle(.secondary)
                    connectionSection
                    if service.hasAccess { calendarsSection }
                    StudySessionsView()
                    preferencesSection
                    tasksSection
                    if let error = service.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
                    if let status = service.status { Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green).textSelection(.enabled) }
                    HStack {
                        Button("Generate study plan", systemImage: "calendar.badge.clock") { generate() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(service.working || aiTaskID != nil || !tasks.contains(where: \.selected))
                        Text("Earlier deadlines first · breaks included · no overlapping sessions").font(.caption).foregroundStyle(.secondary)
                    }
                    if let plan { preview(plan) }
                }.padding(28)
            }
        }.frame(minWidth: 850, idealWidth: 1000, maxWidth: 1100, minHeight: 650, idealHeight: 800)
            .task {
                guard !configured else { return }; configured = true
                if let folder = context.container.configurations.first?.url.deletingLastPathComponent() { service.configure(folder: folder) }
                if service.hasAccess { refresh() } else { rebuildTasks() }
            }
            .onChange(of: assignments.map(\.record)) { _, _ in if configured { rebuildTasks(); plan = nil } }
            .onChange(of: tasks) { _, new in if new != generatedTasks { plan = nil }; service.status = nil }
            .onChange(of: service.settings.preferences) { old, new in
                plan = nil
                if old.days != new.days && service.hasAccess { service.needsRefresh = true }
            }
            .onChange(of: service.settings.deadlineCalendarIDs) { _, _ in rebuildTasks(); plan = nil }
            .onChange(of: service.settings.busyCalendarIDs) { _, _ in plan = nil }
            .onChange(of: service.settings.destinationID) { _, _ in plan = nil }
            .interactiveDismissDisabled(aiTaskID != nil || service.working)
            .onDisappear { aiRequest?.cancel() }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1. Connect Google Calendar", systemImage: "calendar.badge.plus").font(.headline)
            Text("In Apple Calendar, choose Calendar → Add Account → Google, sign in, and enable Calendars. StudyPilot reads that synced account through macOS; it does not need your Google password or an API key.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Apple Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
                Button(service.hasAccess ? "Refresh calendars" : "Connect calendars") {
                    if service.hasAccess { refresh() }
                    else { Task { await service.connect(); rebuildTasks() } }
                }.disabled(service.working)
                if service.working { ProgressView().controlSize(.small) }
                if let date = service.lastRefresh { Text("Read from this Mac \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            if !service.hasAccess { Text("You can also plan existing StudyPilot assignments without connecting a calendar. External commitments will only be checked after connection.").font(.caption).foregroundStyle(.secondary) }
            Text("Google changes appear after macOS syncs them. Calendar → View → Refresh Calendars can request a sync before refreshing here.").font(.caption).foregroundStyle(.secondary)
        }.pilotCard()
    }
    private var calendarsSection: some View {
        @Bindable var service = service
        return         VStack(alignment: .leading, spacing: 12) {
            Text("Which calendars contain your assignments?").font(.headline)
            Text("Mark deadline calendars to list their events below, then select the actual assignments. Busy calendars protect your existing commitments. Selected assignments are treated as deadlines, not occupied time. All-day deadlines are due at 23:59 on their final day.").font(.caption).foregroundStyle(.secondary)
            ForEach(service.calendars) { calendar in
                HStack {
                    Text(calendar.label).frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Assignments", isOn: membership(calendar.id, keyPath: \.deadlineCalendarIDs)).toggleStyle(.checkbox).frame(width: 120)
                    Toggle("Busy time", isOn: membership(calendar.id, keyPath: \.busyCalendarIDs)).toggleStyle(.checkbox).frame(width: 110)
                }
            }
            if service.calendars.isEmpty { Text("No calendars found. Add your Google account in Apple Calendar, let it sync, then refresh.").foregroundStyle(.secondary) }
            Picker("Add study blocks to", selection: $service.settings.destinationID) {
                Text("Choose a destination…").tag("")
                ForEach(service.calendars.filter(\.writable)) { Text($0.label).tag($0.id) }
            }
            Text("Choose a calendar in your Google account to sync study blocks back to Google. The destination is always checked for conflicts.").font(.caption).foregroundStyle(.secondary)
        }.pilotCard()
    }
    private var preferencesSection: some View {
        @Bindable var service = service
        return         VStack(alignment: .leading, spacing: 14) {
            Text("2. Your study time").font(.headline)
            HStack(spacing: 20) {
                Picker("Plan ahead", selection: $service.settings.preferences.days) { Text("7 days").tag(7); Text("14 days").tag(14); Text("28 days").tag(28) }.frame(width: 190)
                DatePicker("From", selection: clockBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: clockBinding(\.endMinute), displayedComponents: .hourAndMinute)
            }
            HStack {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(get: { service.settings.preferences.weekdays.contains(day) }, set: { enabled in
                        if enabled { service.settings.preferences.weekdays.insert(day) } else { service.settings.preferences.weekdays.remove(day) }
                    })).toggleStyle(.checkbox)
                }
            }
            HStack(spacing: 22) {
                Picker("Study blocks", selection: $service.settings.preferences.sessionMinutes) { Text("25 min").tag(25); Text("50 min").tag(50); Text("60 min").tag(60) }
                Stepper("Break: \(service.settings.preferences.breakMinutes) min", value: $service.settings.preferences.breakMinutes, in: 0...30, step: 5)
                Stepper("Daily limit: \(service.settings.preferences.dailyMinutes) min", value: $service.settings.preferences.dailyMinutes, in: 30...480, step: 30)
            }
            Toggle("Automatically reschedule unchecked blocks after they end", isOn: Binding(get: { service.automaticallyReschedules }, set: { service.settings.autoReschedule = $0; persist() }))
            Text("Checks every minute while StudyPilot is open, and catches up when reopened. Unchecked means unfinished. Moves study blocks within your study hours before the deadline; assignment deadlines stay unchanged.").font(.caption).foregroundStyle(.secondary)
            Text("Times use this Mac’s time zone: \(TimeZone.current.identifier). The same study window applies to each selected day. Defaults are editable.").font(.caption).foregroundStyle(.secondary)
        }.pilotCard()
    }
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("3. Choose what to work on").font(.headline)
                Spacer()
                Text("\(tasks.filter(\.selected).count) selected").font(.caption).foregroundStyle(.secondary)
            }
            Text("Minutes are the work still remaining, including any future StudyPilot blocks already on your calendar. Google assignments start with an editable 60-minute estimate. Plans round up to five minutes. Past blocks do not automatically mark work complete.").font(.caption).foregroundStyle(.secondary)
            if let reason = StudyPlanningAI.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            else { Label("AI suggestions run on this Mac. Review the estimated time and steps before planning.", systemImage: "sparkles").font(.caption).foregroundStyle(Color.pilot) }
            if aiTaskID != nil { Button("Cancel AI suggestion") { aiRequest?.cancel(); aiRequestID = nil; aiTaskID = nil } }
            if tasks.isEmpty { Text("Choose an assignment calendar above, or create an assignment in StudyPilot. Upcoming calendar deadlines and the last seven days appear here.").foregroundStyle(.secondary).padding(.vertical) }
            ForEach($tasks) { $task in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Toggle(isOn: $task.selected) { VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.headline)
                            Text("\(task.id.hasPrefix("calendar:") ? "Calendar" : "StudyPilot") · Due \(task.deadline.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        } }.toggleStyle(.checkbox)
                        Spacer()
                        TextField("Minutes", value: $task.minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 65).accessibilityLabel("Remaining minutes for \(task.title)")
                        Text("min").foregroundStyle(.secondary)
                        Picker("Priority", selection: $task.priority) { Text("Low").tag(0); Text("Normal").tag(1); Text("High").tag(2) }.labelsHidden().frame(width: 100)
                        Button(aiTaskID == task.id ? "Thinking…" : "AI estimate & steps") { suggest(task) }
                            .disabled(aiTaskID != nil || StudyPlanningAI.unavailableReason != nil)
                    }
                    if !task.steps.isEmpty { Text(task.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(14).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }.pilotCard()
    }
    private func preview(_ value: StudyPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("4. Your proposed schedule").font(.headline); Spacer(); Text("\(value.blocks.count) blocks · \(value.blocks.reduce(0) { $0 + $1.minutes }) min").foregroundStyle(.secondary) }
            if value.alreadyPlannedMinutes > 0 { Text("\(value.alreadyPlannedMinutes) minutes are already covered by upcoming StudyPilot blocks.").font(.callout).foregroundStyle(.secondary) }
            ForEach(value.unscheduled) { item in Label("\(item.title): \(item.minutes) min still need time. \(item.reason)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            ForEach(value.blocks) { block in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(block.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.subheadline.bold())
                        Text("\(block.start.formatted(date: .omitted, time: .shortened)) – \(block.end.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 160, alignment: .leading)
                    Text(block.title).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(block.minutes) min").monospacedDigit().foregroundStyle(.secondary)
                }.padding(.vertical, 5)
            }
            if !value.blocks.isEmpty {
                Divider()
                Text("Adjust your work estimates or study hours and regenerate if needed. Only the blocks shown above will be added.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save in StudyPilot") { saveLocally(value) }.disabled(service.working)
                    if service.hasAccess {
                        Button("Add to \(service.calendars.first { $0.id == service.settings.destinationID }?.title ?? "calendar")") { publish(value) }
                            .buttonStyle(.borderedProminent).disabled(service.settings.destinationID.isEmpty || service.working)
                    }
                }
            } else if value.unscheduled.isEmpty { Text("All selected work already has study time scheduled.").foregroundStyle(.secondary) }
        }.pilotCard()
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
            if let saved = previous[item.id] ?? service.settings.taskOverrides[item.id] { item.minutes = saved.minutes; item.priority = saved.priority; item.steps = saved.steps; item.selected = saved.selected }
            return item
        }.sorted { $0.deadline < $1.deadline }
    }
    private func persist() { do { try service.saveSettings(tasks: tasks) } catch { service.error = error.localizedDescription } }
    private func refresh() {
        plan = nil; service.error = nil
        do { try service.refresh(); rebuildTasks() } catch { service.error = error.localizedDescription }
    }
    private func suggest(_ task: PlanningTask) {
        aiTaskID = task.id; service.error = nil
        let requestID = UUID(); aiRequestID = requestID
        aiRequest = Task {
            defer { if aiRequestID == requestID { aiTaskID = nil; aiRequestID = nil } }
            do {
                let suggestion = try await StudyPlanningAI.suggest(for: task)
                try Task.checkCancellation()
                guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
                tasks[index].minutes = suggestion.minutes; tasks[index].steps = suggestion.steps
            } catch { if !Task.isCancelled { service.error = error.localizedDescription } }
        }
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
            generatedTasks = tasks; plan = generated
        } catch { service.error = error.localizedDescription }
    }
    private func validate(_ value: StudyPlan) throws {
        guard aiTaskID == nil else { throw PlanningError.invalid("Wait for the AI suggestion, then regenerate the preview.") }
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
            try context.save(); plan = nil; service.status = "Saved \(value.blocks.count) study blocks in StudyPilot."
        } catch { if inserted { context.rollback() }; service.error = error.localizedDescription }
    }
    private func publish(_ value: StudyPlan) {
        do { try validate(value); try service.publish(value, tasks: tasks); plan = nil }
        catch { service.error = error.localizedDescription }
    }
}
