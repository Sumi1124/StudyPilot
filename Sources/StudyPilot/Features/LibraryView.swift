import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct LibraryView: View {
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \Project.title) private var projects: [Project]
    @LiveQuery private var tasks: [Assignment]
    @State private var editingSubject: Subject?
    @State private var newSubject = false
    @State private var editingProject: Project?
    @State private var newProject = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "A place for every idea", title: "Subjects & projects", subtitle: "Shape your workspace around what you’re learning.")
                HStack { Text("Your subjects").font(.title3.bold()); Spacer(); Button("Add subject", systemImage: "plus") { newSubject = true } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                    ForEach(subjects) { subject in
                        Button { editingSubject = subject } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: subject.symbol).font(.title2).foregroundStyle(subject.color).frame(width: 44, height: 44).background(subject.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                Text(subject.name).font(.headline).foregroundStyle(.primary)
                                Text("\(tasks.filter { $0.subjectID == subject.id && !$0.isDone }.count) active assignments · target \(subject.target)/8").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
                        }.buttonStyle(.plain).help("Edit \(subject.name)")
                    }
                }
                HStack { Text("Projects").font(.title3.bold()); Spacer(); Button("New project", systemImage: "plus") { newProject = true } }
                if projects.isEmpty { EmptyState(symbol: "folder", title: "Give a bigger idea a home", message: "Group related assignments into a project, such as your personal project or an investigation.").pilotCard() }
                ForEach(projects) { project in
                    HStack(spacing: 18) {
                        Image(systemName: "folder.fill").font(.title2).foregroundStyle(Color.pilot)
                        VStack(alignment: .leading, spacing: 6) { Text(project.title).font(.headline); Text(project.details).lineLimit(2).foregroundStyle(.secondary) }
                        Spacer()
                        Text("\(tasks.filter { $0.projectID == project.id && $0.isDone }.count)/\(tasks.filter { $0.projectID == project.id }.count) complete").font(.caption).foregroundStyle(.secondary)
                        Button("Assignments") { app.selectedProjectID = project.id; app.section = .assignments }
                        Button("Edit") { editingProject = project }
                    }.pilotCard()
                }
            }.padding(30)
        }
        .sheet(isPresented: $newSubject) { SubjectEditor() }
        .sheet(item: $editingSubject) { SubjectEditor(subject: $0) }
        .sheet(isPresented: $newProject) { ProjectEditor() }
        .sheet(item: $editingProject) { ProjectEditor(project: $0) }
    }
}
struct SubjectEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let subject: Subject?
    @State private var draft: SubjectRecord
    private let colors = ["6877E8", "2B998C", "CF8955", "A178C5", "D06785", "448FBF"]
    init(subject: Subject? = nil) { self.subject = subject; _draft = State(initialValue: subject?.record ?? SubjectRecord()) }
    var body: some View {
        VStack(spacing: 0) {
            Text(subject == nil ? "New subject" : "Edit subject").font(.title2.bold()).padding(24)
            Form {
                TextField("Name", text: $draft.name)
                Picker("Color", selection: $draft.colorHex) {
                    ForEach(Array(zip(colors, ["Iris", "Teal", "Amber", "Violet", "Rose", "Blue"])), id: \.0) { hex, name in Text(name).tag(hex) }
                }
                Picker("Icon", selection: $draft.symbol) {
                    ForEach(["book.closed", "function", "atom", "text.book.closed", "globe.europe.africa", "pencil.and.ruler", "music.note", "figure.run"], id: \.self) { Label($0, systemImage: $0).tag($0) }
                }
                Stepper("Personal criterion target: \(draft.target)/8", value: $draft.target, in: 0...8)
                Text("This is your personal target for each criterion, not an official grade boundary.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            SheetActions(title: "Save subject", disabled: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }) {
                draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let subject { subject.apply(draft) } else { context.insert(Subject(draft)) }
                if app.save(context) { dismiss() }
            }
        }.frame(width: 490, height: 400)
    }
}
struct ProjectEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    let project: Project?
    @State private var draft: ProjectRecord
    init(project: Project? = nil) { self.project = project; _draft = State(initialValue: project?.record ?? ProjectRecord()) }
    var body: some View {
        VStack(spacing: 0) {
            Text(project == nil ? "New project" : "Edit project").font(.title2.bold()).padding(24)
            Form {
                TextField("Title", text: $draft.title)
                TextField("Description", text: $draft.details, axis: .vertical).lineLimit(3...5)
                SubjectPicker(subjects: subjects, selection: $draft.subjectID)
            }.formStyle(.grouped)
            SheetActions(title: "Save project", disabled: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }) {
                draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if let project { project.apply(draft) } else { context.insert(Project(draft)) }
                if app.save(context) { dismiss() }
            }
        }.frame(width: 520, height: 370)
    }
}
