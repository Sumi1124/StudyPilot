import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct QuickTaskEntry: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    var compact = false
    @State private var title = ""
    @State private var due = TodayWorkspace.defaultDeadline(now: Date())
    @State private var subjectID: UUID?
    @State private var minutes = 30
    @State private var saved: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("New assignment").font(.system(size: 13, weight: .semibold)); Spacer(); Button("More…") { app.showingAssignment = true }.font(.caption).buttonStyle(.link) }
            if compact {
                TextField("Assignment title", text: $title).textFieldStyle(.roundedBorder).onSubmit(add)
                DatePicker("Due", selection: $due).font(.caption)
                SubjectPicker(subjects: subjects, selection: $subjectID).font(.caption)
                effort.font(.caption)
                Button("Add assignment", systemImage: "plus", action: add).frame(maxWidth: .infinity).buttonStyle(.borderedProminent).disabled(invalid)
            } else {
                HStack {
                    TextField("Assignment title", text: $title).textFieldStyle(.roundedBorder).onSubmit(add)
                    Button("Add assignment", systemImage: "plus", action: add).buttonStyle(.borderedProminent).disabled(invalid)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { fields }
                    VStack(alignment: .leading, spacing: 10) { fields }
                }
            }
            if let saved { Text(saved).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var invalid: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 500 }
    private var effort: some View { Picker("Effort", selection: $minutes) { ForEach([15,30,60,90,120], id: \.self) { Text("\($0) min").tag($0) } } }
    @ViewBuilder private var fields: some View {
        DatePicker("Due", selection: $due).fixedSize()
        SubjectPicker(subjects: subjects, selection: $subjectID).frame(maxWidth: 210)
        effort.frame(width: 145)
    }
    private func add() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !invalid else { return }
        let item = Assignment(AssignmentRecord(title: clean, subjectID: subjectID, dueDate: due, estimatedMinutes: minutes))
        context.insert(item)
        do { try context.save(); title = ""; saved = "Added \(clean)." }
        catch { context.delete(item); app.error = "The task could not be saved: \(error.localizedDescription)" }
    }
}
