import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

enum FirstRunDestination {
    case planner, focus, dashboard
}

struct FirstRunSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(CalendarPlanningService.self) private var planning
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var step = 0
    @State private var title = ""
    @State private var due = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var minutes = 120
    @State private var subjectID: UUID?
    @State private var createdAssignmentID: UUID?
    @State private var sampleLoaded = false
    @State private var working = false
    @State private var message: String?
    let complete: (FirstRunDestination) -> Void

    private let steps = ["Welcome", "Deadline", "Calendar", "Ready"]
    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSaveDeadline: Bool { !cleanTitle.isEmpty && (5...100_000).contains(minutes) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch step {
                case 0: welcome
                case 1: deadline
                case 2: calendar
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 820, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 11) {
                    Image(systemName: "book.closed.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Color.pilot.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set up StudyPilot").font(.title2.bold())
                        Text("Your first useful plan in a few minutes").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Skip for now") { complete(.dashboard) }.buttonStyle(.link)
            }
            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 7) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                        Text(name).font(.system(size: 11, weight: index == step ? .semibold : .regular))
                    }
                    .foregroundStyle(index <= step ? Color.pilot : Color.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(index == step ? Color.pilot.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding(24)
    }

    private var welcome: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Turn one deadline into a calm plan.").font(.system(size: 34, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("Add the work, let StudyPilot protect your existing calendar time, and begin one focused session. You can explore everything else later.")
                    .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 13) {
                    journeyRow(1, "Enter a real deadline", "Give the planner a task and a clear amount of work.")
                    journeyRow(2, "Plan around your calendar", "Classes and commitments stay protected.")
                    journeyRow(3, "Start focusing", "Move directly from planning into a 25-minute session.")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 62, weight: .light)).foregroundStyle(Color.pilot)
                    .frame(width: 150, height: 150).background(Color.pilot.opacity(0.09), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                Text("No account required").font(.headline)
                Text("Your assignments, notes, and plans stay on this Mac.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(width: 245).padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }.padding(34)
    }

    private var deadline: some View {
        VStack(alignment: .leading, spacing: 24) {
            setupTitle("Start with one deadline", detail: "Use something real. You can add the rest after seeing the first plan.")
            VStack(alignment: .leading, spacing: 18) {
                TextField("Assignment title", text: $title).textFieldStyle(.roundedBorder).font(.title3)
                DatePicker("Deadline", selection: $due).datePickerStyle(.compact)
                SubjectPicker(subjects: subjects, selection: $subjectID)
                HStack {
                    Text("Estimated work left")
                    Spacer()
                    TextField("Minutes", value: $minutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 110).monospacedDigit()
                    Text("min").foregroundStyle(.secondary)
                    Stepper("Adjust minutes", value: $minutes, in: 5...100_000, step: 5).labelsHidden()
                }
                Text("Enter the full amount, such as 200 minutes. StudyPilot will split it into shorter sessions.").font(.caption).foregroundStyle(.secondary)
            }.pilotCard()
            if let message { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
        }.padding(34)
    }

    private var calendar: some View {
        VStack(alignment: .leading, spacing: 22) {
            setupTitle("Protect the time already on your calendar", detail: "Calendar access is optional. When connected, StudyPilot avoids classes, appointments, and other selected commitments.")
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: planning.hasAccess ? "calendar.badge.checkmark" : "calendar.badge.plus").font(.title).foregroundStyle(Color.pilot)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planning.hasAccess ? "Calendars connected" : "Connect Apple Calendar").font(.headline)
                        Text(planning.hasAccess ? "Choose which calendars should block study time." : "Google calendars already added to macOS appear through Apple Calendar.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if planning.hasAccess {
                        Button("Refresh", systemImage: "arrow.clockwise") { refreshCalendars() }.disabled(working)
                    } else {
                        Button("Connect calendars") { connectCalendars() }.buttonStyle(.borderedProminent).disabled(working)
                    }
                }
                if working { ProgressView("Reading calendars…").controlSize(.small) }
                if planning.hasAccess {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(planning.calendars) { calendar in
                                Toggle(isOn: busyCalendar(calendar.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(calendar.title)
                                        Text(calendar.account).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.toggleStyle(.checkbox)
                            }
                        }
                    }.frame(maxHeight: 185)
                    Picker("Save study blocks to", selection: destinationCalendar) {
                        Text("StudyPilot only").tag("")
                        ForEach(planning.calendars.filter(\.writable)) { Text($0.label).tag($0.id) }
                    }
                    Text("You review every study block before it is saved. Google synchronization is handled by macOS Calendar.").font(.caption).foregroundStyle(.secondary)
                }
            }.pilotCard()
            if let message { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
        }.padding(34)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 24) {
            setupTitle("Your workspace is ready", detail: "The planner will use your deadline, work estimate, preferred study hours, and calendar conflicts.")
            HStack(spacing: 14) {
                resultCard(symbol: "checkmark.circle.fill", title: sampleLoaded ? "Sample workspace added" : "Deadline added", detail: createdTitle)
                resultCard(symbol: planning.hasAccess ? "calendar.badge.checkmark" : "calendar", title: planning.hasAccess ? "Calendar protected" : "Local planning", detail: planning.hasAccess ? "\(planning.settings.busyCalendarIDs.count) calendars checked" : "Connect later if you want")
                resultCard(symbol: "timer", title: "Focus is next", detail: "Start after reviewing the plan")
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("What happens next", systemImage: "sparkles").font(.headline).foregroundStyle(Color.pilot)
                Text("Choose the assignment, confirm your usual study hours, preview the sessions, and save. The final screen can start your first focus session immediately.").foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.pilot.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.padding(34)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 { Button("Back") { step -= 1; message = nil }.disabled(working) }
            Spacer()
            switch step {
            case 0:
                Button("Explore a sample workspace") { loadSampleWorkspace() }.disabled(working)
                Button("Set up my workspace", systemImage: "arrow.right") { step = 1 }.buttonStyle(.borderedProminent)
            case 1:
                Button("Continue", systemImage: "arrow.right") { saveDeadline() }.buttonStyle(.borderedProminent).disabled(!canSaveDeadline || working)
            case 2:
                Button(planning.hasAccess ? "Continue" : "Continue without calendar", systemImage: "arrow.right") { if saveCalendarChoices() { step = 3 } }.buttonStyle(.borderedProminent).disabled(working)
            default:
                Button("Open my workspace") { complete(.dashboard) }
                Button("Build my study plan", systemImage: "calendar.badge.clock") { complete(.planner) }.buttonStyle(.borderedProminent)
            }
        }.padding(20).background(.bar)
    }

    private var createdTitle: String {
        if let id = createdAssignmentID, let item = assignments.first(where: { $0.id == id }) { return item.title }
        return assignments.first?.title ?? "Your first assignment"
    }

    private var destinationCalendar: Binding<String> {
        Binding(get: { planning.settings.destinationID }, set: { planning.settings.destinationID = $0 })
    }

    private func busyCalendar(_ id: String) -> Binding<Bool> {
        Binding(get: { planning.settings.busyCalendarIDs.contains(id) }, set: { enabled in
            if enabled { planning.settings.busyCalendarIDs.insert(id) } else { planning.settings.busyCalendarIDs.remove(id) }
        })
    }

    private func journeyRow(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.caption.bold()).foregroundStyle(.white).frame(width: 24, height: 24).background(Color.pilot, in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func setupTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 27, weight: .semibold)); Text(detail).font(.callout).foregroundStyle(.secondary) }
    }

    private func resultCard(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.pilot)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading).pilotCard()
    }

    private func saveDeadline() {
        message = nil
        guard canSaveDeadline else { message = "Enter a title and at least 5 minutes."; return }
        if let id = createdAssignmentID, let item = assignments.first(where: { $0.id == id }) {
            var record = item.record
            record.title = cleanTitle; record.dueDate = due; record.subjectID = subjectID; record.estimatedMinutes = minutes
            item.apply(record)
        } else {
            let record = AssignmentRecord(title: cleanTitle, subjectID: subjectID, dueDate: due, estimatedMinutes: minutes)
            context.insert(Assignment(record)); createdAssignmentID = record.id
        }
        do { try context.save(); step = 2 }
        catch { context.rollback(); message = "The deadline could not be saved: \(error.localizedDescription)" }
    }

    private func loadSampleWorkspace() {
        message = nil; working = true
        defer { working = false }
        guard !sampleLoaded else { step = 2; return }
        if let existing = assignments.first(where: { $0.title == "Quadratic equations practice" }) {
            createdAssignmentID = existing.id; sampleLoaded = true; title = existing.title; due = existing.dueDate; minutes = existing.estimatedMinutes; subjectID = existing.subjectID; step = 2; return
        }
        let math = subjects.first { $0.name.localizedCaseInsensitiveContains("math") }?.id ?? subjects.first?.id
        let humanities = subjects.first { $0.name.localizedCaseInsensitiveContains("human") || $0.name.localizedCaseInsensitiveContains("history") }?.id
        let first = AssignmentRecord(title: "Quadratic equations practice", subjectID: math, dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(), priority: 2, estimatedMinutes: 200, checklist: [ChecklistItem(title: "Review class examples"), ChecklistItem(title: "Complete practice questions")])
        let second = AssignmentRecord(title: "History source reflection", subjectID: humanities, dueDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date(), estimatedMinutes: 75)
        let notebook = NotebookRecord(title: "Starter study notebook", subjectID: math)
        context.insert(Assignment(first)); context.insert(Assignment(second)); context.insert(Notebook(notebook))
        context.insert(Note(NoteRecord(title: "Quadratic equations", body: "Key idea: identify a, b, and c before choosing a method.\n\nDiscriminant :: b² − 4ac", notebookID: notebook.id, subjectID: math, tags: ["sample", "math"])))
        do {
            try context.save(); createdAssignmentID = first.id; sampleLoaded = true; title = first.title; due = first.dueDate; minutes = first.estimatedMinutes; subjectID = first.subjectID; step = 2
        } catch { context.rollback(); message = "The sample workspace could not be created: \(error.localizedDescription)" }
    }

    private func connectCalendars() {
        working = true; message = nil
        Task { @MainActor in
            await planning.connect()
            working = false
            if planning.hasAccess, planning.settings.destinationID.isEmpty { planning.settings.destinationID = planning.calendars.first(where: \.writable)?.id ?? "" }
            if let error = planning.error { message = error }
        }
    }

    private func refreshCalendars() {
        working = true; message = nil
        defer { working = false }
        do { try planning.refresh() } catch { message = error.localizedDescription }
    }

    private func saveCalendarChoices() -> Bool {
        do { try planning.saveSettings(); return true }
        catch { message = error.localizedDescription; return false }
    }
}
