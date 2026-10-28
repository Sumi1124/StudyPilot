import SwiftUI
import StudyPilotData

private struct SearchResult: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void
}
struct CommandPalette: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \Project.title) private var projects: [Project]
    @LiveQuery(sort: \Deck.title) private var decks: [Deck]
    @LiveQuery(sort: \Notebook.title) private var notebooks: [Notebook]
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool
    private var results: [SearchResult] {
        var result: [SearchResult] = [
            SearchResult(id: "new-assignment", title: "New assignment", detail: "⌘N", symbol: "plus.circle") { app.showingAssignment = true },
            SearchResult(id: "new-note", title: "New note", detail: "⇧⌘N", symbol: "square.and.pencil") { app.section = .notes; app.createNote = true },
            SearchResult(id: "start-focus", title: focus.state == nil ? "Start a 25-minute focus session" : "Open active focus session", detail: "⇧⌘F", symbol: "timer") { app.section = .focus; if focus.state == nil { focus.start(minutes: 25, subjectID: nil) } }
        ].filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
        for section in AppSection.allCases where query.isEmpty || section.rawValue.localizedCaseInsensitiveContains(query) {
            result.append(SearchResult(id: "section-\(section.id)", title: "Open \(section.rawValue)", detail: "Navigate", symbol: section.symbol) { app.section = section })
        }
        if query.isEmpty { return result }
        for item in assignments.filter({ "\($0.title) \($0.details)".localizedCaseInsensitiveContains(query) }).prefix(10) {
            result.append(SearchResult(id: "assignment-\(item.id)", title: item.title, detail: "Assignment · \(item.status)", symbol: "checklist") { app.selectedAssignmentID = item.id; app.section = .assignments })
        }
        for item in notes.filter({ "\($0.title) \($0.body) \($0.tags.joined(separator: " "))".localizedCaseInsensitiveContains(query) }).prefix(10) {
            result.append(SearchResult(id: "note-\(item.id)", title: item.title, detail: "Note", symbol: "note.text") { app.selectedNoteID = item.id; app.section = .notes })
        }
        for item in notebooks.filter({ $0.title.localizedCaseInsensitiveContains(query) }).prefix(10) {
            result.append(SearchResult(id: "notebook-\(item.id)", title: item.title, detail: "Notebook · sources & notes", symbol: "books.vertical") { app.selectedNotebookID = item.id; app.section = .notebooks })
        }
        for item in subjects.filter({ $0.name.localizedCaseInsensitiveContains(query) }).prefix(10) {
            result.append(SearchResult(id: "subject-\(item.id)", title: item.name, detail: "Subject progress", symbol: item.symbol) { app.selectedSubjectID = item.id; app.section = .progress })
        }
        for item in projects.filter({ "\($0.title) \($0.details)".localizedCaseInsensitiveContains(query) }).prefix(10) {
            result.append(SearchResult(id: "project-\(item.id)", title: item.title, detail: "Project assignments", symbol: "folder") { app.selectedProjectID = item.id; app.section = .assignments })
        }
        for item in decks.filter({ $0.title.localizedCaseInsensitiveContains(query) }).prefix(10) {
            result.append(SearchResult(id: "deck-\(item.id)", title: item.title, detail: "Flashcard deck", symbol: "rectangle.on.rectangle") { app.selectedDeckID = item.id; app.section = .revision })
        }
        return result
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(Color.pilot)
                TextField("Search your workspace, or take an action…", text: $query).font(.title3).textFieldStyle(.plain).focused($searchFocused).onSubmit(runSelected)
                Button("esc") { dismiss() }.font(.caption).keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if results.isEmpty { EmptyState(symbol: "magnifyingglass", title: "No matches yet", message: "Try a title, subject, tag, or a phrase from your notes.") }
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            Button { run(result) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: result.symbol).font(.title3).foregroundStyle(Color.pilot).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 5) { Text(result.title).font(.headline).lineLimit(1); Text(result.detail).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    if index == highlighted { Image(systemName: "return").foregroundStyle(.tertiary) }
                                }.padding(14).contentShape(Rectangle()).background(index == highlighted ? Color.pilot.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).id(result.id)
                        }
                    }.padding(12).id(query)
                }.onChange(of: highlighted) { if results.indices.contains(highlighted) { proxy.scrollTo(results[highlighted].id) } }
            }
            Divider()
            HStack { Text("↑ ↓ to move · Return to open"); Spacer(); Text("Your work, a few keystrokes away.") }.font(.caption).foregroundStyle(.tertiary).padding(16)
        }.frame(width: 660, height: 530)
            .onAppear { searchFocused = true }
            .onChange(of: query) { highlighted = 0 }
            .onKeyPress(.downArrow) { highlighted = min(max(0, results.count - 1), highlighted + 1); return .handled }
            .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
    }
    private func runSelected() { if results.indices.contains(highlighted) { run(results[highlighted]) } }
    private func run(_ result: SearchResult) {
        dismiss()
        // Let the palette dismiss before presenting a second sheet.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            result.action()
        }
    }
}
