import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct QuickTaskEntry: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var title = ""
    @State private var due = TodayWorkspace.defaultDeadline(now: Date())
    @State private var subjectID: UUID?
    @State private var minutes = 30
    @State private var saved: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Quick add", systemImage: "plus.circle.fill").font(.headline); Spacer(); Button("Full editor") { app.showingAssignment = true }.font(.caption) }
            HStack {
                TextField("What do you need to do?", text: $title).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add task", systemImage: "plus", action: add).buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 500)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { fields }
                VStack(alignment: .leading, spacing: 10) { fields }
            }
            if let saved { Text(saved).font(.caption).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var fields: some View {
        DatePicker("Due", selection: $due).fixedSize()
        SubjectPicker(subjects: subjects, selection: $subjectID).frame(maxWidth: 210)
        Picker("Effort", selection: $minutes) { ForEach([15, 30, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) } }.frame(width: 145)
    }
    private func add() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 500 else { return }
        let item = Assignment(AssignmentRecord(title: clean, subjectID: subjectID, dueDate: due, estimatedMinutes: minutes))
        context.insert(item)
        do { try context.save(); title = ""; saved = "Added \(clean)." }
        catch { context.delete(item); app.error = "The task could not be saved: \(error.localizedDescription)" }
    }
}
