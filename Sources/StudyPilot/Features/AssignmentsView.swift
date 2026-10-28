import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct AssignmentsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \Project.title) private var projects: [Project]
    @State private var search = ""
    @State private var status = "Active"
    @State private var subjectID: UUID?
    @State private var projectID: UUID?
    @State private var sort = "Deadline"
    @State private var editing: Assignment?
    @State private var deleting: Assignment?
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var bulkMessage: String?

    private var filtered: [Assignment] {
        let result = assignments.filter { item in
            (status == "All" || (status == "Active" ? !item.isDone : item.status == status)) &&
            (subjectID == nil || item.subjectID == subjectID) && (projectID == nil || item.projectID == projectID) &&
            (search.isEmpty || "\(item.title) \(item.details)".localizedCaseInsensitiveContains(search)) && app.assignmentTimeFilter.includes(item.record, now: app.now)
        }
        return result.sorted {
            switch sort {
            case "Priority": $0.priority == $1.priority ? $0.dueDate < $1.dueDate : $0.priority > $1.priority
            case "Title": $0.title.localizedStandardCompare($1.title) == .orderedAscending
            default: $0.dueDate < $1.dueDate
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "Make room for your best work", title: "Assignments", subtitle: "Deadlines, priorities, and your own checklists.")
                QuickTaskEntry().pilotCard()
                Picker("Deadline filter", selection: Binding(get: { app.assignmentTimeFilter }, set: { app.assignmentTimeFilter = $0 })) {
                    ForEach(AssignmentTimeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                HStack {
                    TextField("Search assignments", text: $search).textFieldStyle(.roundedBorder).frame(minWidth: 130)
                    Picker("Status", selection: $status) { ForEach(["Active", "All"] + TaskStatus.allCases.map(\.rawValue), id: \.self) { Text($0) } }.labelsHidden().frame(width: 130)
                    SubjectPicker(subjects: subjects, selection: $subjectID, emptyLabel: "All subjects").labelsHidden().frame(width: 160)
                    Picker("Sort", selection: $sort) { ForEach(["Deadline", "Priority", "Title"], id: \.self) { Text($0) } }.frame(width: 150)
                }
                if !projects.isEmpty {
                    Picker("Project", selection: $projectID) {
                        Text("All projects").tag(nil as UUID?)
                        ForEach(projects) { Text($0.title).tag(Optional($0.id)) }
                    }.frame(maxWidth: 300)
                }
                HStack {
                    Button(selecting ? "Done selecting" : "Select assignments") { selecting.toggle(); selectedIDs.removeAll(); bulkMessage = nil }
                    if selecting {
                        Text("\(selectedIDs.count) selected").font(.caption)
                        Button("Select visible") { selectedIDs = Set(filtered.map(\.id)) }
                        Button("Clear") { selectedIDs.removeAll() }
                        Menu("Set status") {
                            ForEach(TaskStatus.allCases, id: \.self) { value in Button(value.rawValue) { applyBulk(.status(value)) } }
                        }.disabled(selectedIDs.isEmpty)
                        Button("Postpone 1 day") { applyBulk(.shiftDays(1)) }.disabled(selectedIDs.isEmpty)
                    }
                }
                if let bulkMessage { Text(bulkMessage).font(.caption).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    if filtered.isEmpty {
                        EmptyState(symbol: "checklist", title: assignments.isEmpty ? "No assignments yet" : "No matching assignments", message: assignments.isEmpty ? "Add an assignment to start tracking your work." : "Try another subject, status, or search.")
                        if assignments.isEmpty { Button("Add an assignment") { app.showingAssignment = true }.buttonStyle(.borderedProminent).padding(.bottom, 24) }
                    }
                    ForEach(filtered) { assignment in
                        HStack {
                        if selecting {
                            Toggle("Select \(assignment.title)", isOn: Binding(get: { selectedIDs.contains(assignment.id) }, set: { if $0 { selectedIDs.insert(assignment.id) } else { selectedIDs.remove(assignment.id) } })).labelsHidden().toggleStyle(.checkbox)
                        }
                        AssignmentRow(assignment: assignment, subject: subjects.first { $0.id == assignment.subjectID }, edit: { editing = assignment })
                            .contextMenu {
                                Button("Edit assignment") { editing = assignment }
                                Button("Ask AI about this assignment") { app.ask("Help me work on my assignment \(assignment.title).") }
                                Button("Delete assignment…", role: .destructive) { deleting = assignment }
                            }
                        }
                        if assignment.id != filtered.last?.id { Divider().padding(.leading, 56) }
                    }
                }.pilotCard()
            }.padding(30)
        }
        .sheet(item: $editing) { AssignmentEditor(assignment: $0) }
        .alert("Delete this assignment?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { context.delete(deleting); app.save(context) }; deleting = nil }
        } message: { Text("This removes the assignment and its subtasks. Export a backup first if you want to keep a copy.") }
        .onChange(of: filtered.map(\.id)) { _, ids in selectedIDs.formIntersection(ids) }
        .onAppear { openSelection() }
        .onChange(of: app.selectedAssignmentID) { openSelection() }
        .onChange(of: assignments.map(\.id)) { openSelection() }
        .onChange(of: app.selectedProjectID) { projectID = app.selectedProjectID }
    }
    private func applyBulk(_ action: AssignmentBulkAction) {
        let updates = AssignmentActions.updates(records: assignments.map(\.record), selectedIDs: selectedIDs, visibleIDs: Set(filtered.map(\.id)), action: action, now: Date())
        for record in updates { assignments.first { $0.id == record.id }?.apply(record) }
        if app.save(context, completionChanges: updates) { bulkMessage = "Updated \(updates.count) assignments."; selectedIDs.removeAll() }
        else { context.rollback(); bulkMessage = "Changes could not be saved. Please try again." }
    }
    private func openSelection() {
        if let id = app.selectedAssignmentID, let task = assignments.first(where: { $0.id == id }) { editing = task; app.selectedAssignmentID = nil }
        if let id = app.selectedProjectID { projectID = id; app.selectedProjectID = nil }
    }
}

struct AssignmentRow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @Bindable var assignment: Assignment
    let subject: Subject?
    let edit: () -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 14) {
            Button {
                app.toggleCompletion(assignment, context: context)
            } label: {
                Image(systemName: assignment.isDone ? "checkmark.circle.fill" : "circle").font(.system(size: 22, weight: .light)).foregroundStyle(assignment.isDone ? Color.pilot : .secondary)
            }.buttonStyle(.plain).help(assignment.isDone ? "Mark incomplete" : "Complete assignment").accessibilityLabel(assignment.isDone ? "Mark \(assignment.title) incomplete" : "Complete \(assignment.title)")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(assignment.title).font(.system(size: 14, weight: .semibold)).strikethrough(assignment.isDone).foregroundStyle(.primary)
                    HStack(spacing: 12) {
                        SubjectBadge(subject: subject)
                        if !assignment.criteria.isEmpty { Text("Criterion " + assignment.criteria.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                if focus.state != nil { Button("Open active focus session") { app.section = .focus } }
                else {
                    Button("Focus for 25 minutes") { focus.start(minutes: 25, subjectID: assignment.subjectID); app.section = .focus }
                    Button("Focus for 50 minutes") { focus.start(minutes: 50, subjectID: assignment.subjectID); app.section = .focus }
                }
            } label: { Image(systemName: "timer") }.menuStyle(.borderlessButton).frame(width: 28).help("Focus on this subject")
            VStack(alignment: .trailing, spacing: 6) {
                Text(assignment.dueDate, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(PlannerLogic.isOverdue(assignment.record, at: app.now) ? .red : .secondary)
                HStack(spacing: 6) {
                    if assignment.priority == 2 { Text("High priority").foregroundStyle(.orange) }
                    Text(assignment.status).foregroundStyle(.secondary)
                }.font(.system(size: 10, weight: .medium))
            }
        }.padding(.vertical, 12)
        if !assignment.checklist.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(assignment.checklist) { item in
                        Toggle(isOn: Binding(get: { assignment.checklist.first { $0.id == item.id }?.isComplete ?? false }, set: { completed in
                            updateChecklist(item.id, completed: completed)
                        })) { Text(item.title).strikethrough(item.isComplete).foregroundStyle(item.isComplete ? .secondary : .primary) }.toggleStyle(.checkbox)
                    }
                    Text("Finish the assignment separately when all your work is done.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 10)
            } label: {
                HStack(spacing: 10) {
                    Text("Checklist · \(assignment.checklist.filter(\.isComplete).count) of \(assignment.checklist.count)").font(.caption)
                    ProgressView(value: Double(assignment.checklist.filter(\.isComplete).count), total: Double(assignment.checklist.count)).frame(width: 90)
                }
            }.padding(.leading, 36).padding(.bottom, 12)
        }
        }
    }
    private func updateChecklist(_ id: UUID, completed: Bool) {
        let before = assignment.record
        do {
            let after = try AssignmentChecklist.setting(before, itemID: id, completed: completed)
            assignment.apply(after)
            if !app.save(context, updateReminders: false) { assignment.apply(before) }
        } catch { app.error = error.localizedDescription }
    }
}

struct AssignmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(CalendarPlanningService.self) private var planning
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \Project.title) private var projects: [Project]
    let assignment: Assignment?
    @State private var draft: AssignmentRecord
    @State private var reminder: Bool
    @State private var newStep = ""
    @State private var validation: String?
    init(assignment: Assignment? = nil, date: Date? = nil) {
        self.assignment = assignment
        let record = assignment?.record ?? AssignmentRecord(dueDate: date ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        _draft = State(initialValue: record); _reminder = State(initialValue: record.reminderDate != nil)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(assignment == nil ? "New assignment" : "Edit assignment").font(.title2.bold()); Spacer() }.padding(24)
            Form {
                TextField("Title", text: $draft.title)
                TextField("Description", text: $draft.details, axis: .vertical).lineLimit(3...6)
                SubjectPicker(subjects: subjects, selection: $draft.subjectID)
                Picker("Project", selection: $draft.projectID) {
                    Text("No project").tag(nil as UUID?)
                    ForEach(projects) { Text($0.title).tag(Optional($0.id)) }
                }
                DatePicker("Deadline", selection: $draft.dueDate)
                HStack {
                    Picker("Priority", selection: $draft.priority) { Text("Low").tag(0); Text("Normal").tag(1); Text("High").tag(2) }
                    Picker("Status", selection: $draft.status) { ForEach(TaskStatus.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                }
                HStack {
                    Text("Time left")
                    Spacer()
                    TextField("Minutes", value: $draft.estimatedMinutes, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 110).monospacedDigit()
                    Text("min").foregroundStyle(.secondary)
                    Stepper("Adjust estimated minutes", value: $draft.estimatedMinutes, in: 5...100_000, step: 5).labelsHidden()
                }
                TimeEstimateButton(input: EffortEstimateInput(id: draft.id.uuidString, title: draft.title, details: draft.details, subject: subjects.first { $0.id == draft.subjectID }?.name ?? "", deadline: draft.dueDate, checklist: draft.checklist, completed: draft.status == TaskStatus.done.rawValue), minutes: $draft.estimatedMinutes)
                HStack {
                    Text("MYP criteria"); Spacer()
                    ForEach(Criterion.allCases) { criterion in
                        Toggle(criterion.rawValue, isOn: Binding(get: { draft.criteria.contains(criterion.rawValue) }, set: { enabled in
                            draft.criteria.removeAll { $0 == criterion.rawValue }
                            if enabled { draft.criteria.append(criterion.rawValue); draft.criteria.sort() }
                        })).toggleStyle(.button)
                    }
                }
                Toggle("Remind me", isOn: $reminder)
                if reminder {
                    DatePicker("Reminder", selection: Binding(get: { draft.reminderDate ?? draft.dueDate.addingTimeInterval(-3600) }, set: { draft.reminderDate = $0 }))
                    Text("Notifications require permission in StudyPilot Settings.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Small steps") {
                    ForEach($draft.checklist) { $step in
                        HStack {
                            Toggle("Complete step", isOn: $step.isComplete).labelsHidden()
                            TextField("Step", text: $step.title)
                            Button { draft.checklist.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove step from draft")
                        }
                    }
                    HStack {
                        TextField("Add a subtask", text: $newStep).onSubmit(addStep)
                        Button("Add", action: addStep).disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let validation { Text(validation).foregroundStyle(.red) }
            }.formStyle(.grouped)
            SheetActions(title: "Save assignment", disabled: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }, save: save)
        }.frame(width: 620, height: 820)
    }
    private func addStep() {
        let title = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { draft.checklist.append(ChecklistItem(title: title)); newStep = "" }
    }
    private func save() {
        addStep(); draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.reminderDate = reminder ? (draft.reminderDate ?? draft.dueDate.addingTimeInterval(-3600)) : nil
        if let date = draft.reminderDate, date >= draft.dueDate || (date <= Date() && date != assignment?.reminderDate) { validation = "Choose a reminder in the future, before the deadline."; return }
        if draft.checklist.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { validation = "Give every subtask a title, or remove the empty step."; return }
        if !(5...100_000).contains(draft.estimatedMinutes) { validation = "Enter at least 5 minutes of work left."; return }
        draft.completedAt = draft.status == TaskStatus.done.rawValue ? (draft.completedAt ?? Date()) : nil
        let timeChanged = assignment.map { $0.estimatedMinutes != draft.estimatedMinutes } ?? false
        if let assignment { assignment.apply(draft) } else { context.insert(Assignment(draft)) }
        if app.save(context, completionChanges: [draft]) {
            let key = "local:\(draft.id.uuidString)"
            if timeChanged, var saved = planning.settings.taskOverrides[key] {
                saved.minutes = draft.estimatedMinutes; planning.settings.taskOverrides[key] = saved
                do { try planning.saveSettings() }
                catch { app.error = "Assignment saved, but its planner time could not be saved: " + error.localizedDescription }
            }
            dismiss()
        }
    }
}
