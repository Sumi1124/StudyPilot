import SwiftUI
import AppKit
import SwiftData
import StudyPilotCore
import StudyPilotData

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @LiveQuery(sort: \Notebook.title) private var notebooks: [Notebook]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var search = ""
    @State private var notebookID: UUID?
    @State private var subjectID: UUID?
    @State private var selectedID: UUID?
    @State private var notebookSheet = false
    @State private var editingNotebook: Notebook?
    @State private var deleting: Note?
    private var filtered: [Note] {
        notes.filter { note in
            (notebookID == nil || note.notebookID == notebookID) &&
            (subjectID == nil || note.subjectID == subjectID || notebooks.first { $0.id == note.notebookID }?.subjectID == subjectID) &&
            (search.isEmpty || "\(note.title) \(note.body) \(note.tags.joined(separator: " "))".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Notes").font(.system(size: 24, weight: .semibold)); Spacer(); Button(action: addNote) { Image(systemName: "square.and.pencil") }.help("New note (⇧⌘N)") }
                TextField("Search notes & tags", text: $search).textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Notebook", selection: $notebookID) {
                        Text("All notebooks").tag(nil as UUID?)
                        ForEach(notebooks) { Text($0.title).tag(Optional($0.id)) }
                    }.labelsHidden()
                    Menu {
                        Button("New notebook") { notebookSheet = true }
                        if let notebook = notebooks.first(where: { $0.id == notebookID }) { Button("Edit notebook") { editingNotebook = notebook } }
                    } label: { Image(systemName: "folder.badge.plus") }.menuStyle(.borderlessButton).frame(width: 24).help("Notebook actions")
                }
                SubjectPicker(subjects: subjects, selection: $subjectID, emptyLabel: "All subjects").labelsHidden()
                List(selection: $selectedID) {
                    ForEach(filtered) { note in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(note.title.isEmpty ? "Untitled note" : note.title).font(.headline).lineLimit(1)
                            Text(note.body.isEmpty ? "Empty note" : note.body.replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                Text(note.updatedAt, format: .dateTime.month(.abbreviated).day())
                                Spacer()
                                if let tag = note.tags.first { Text("#" + tag) }
                            }.font(.system(size: 10)).foregroundStyle(.tertiary)
                        }.padding(.vertical, 8).tag(note.id)
                            .contextMenu { Button("Delete note…", role: .destructive) { deleting = note } }
                    }
                }.listStyle(.plain)
                Text("\(filtered.count) notes · stored on this Mac").font(.caption).foregroundStyle(.tertiary)
            }.padding(20).frame(minWidth: 230, idealWidth: 265, maxWidth: 320)
            Group {
                if let note = notes.first(where: { $0.id == selectedID }) {
                    NoteEditor(note: note, notebooks: notebooks, subjects: subjects, allNotes: notes) { id in selectedID = id; notebookID = nil; subjectID = nil; search = "" }.id(note.id)
                } else {
                    VStack(spacing: 10) {
                        EmptyState(symbol: "note.text", title: "Select a note", message: "Keep class notes, connect your ideas with [[note titles]], and find them again when you need them.")
                        Button("Write a note", action: addNote).buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $notebookSheet) { NotebookEditor() }
        .sheet(item: $editingNotebook) { NotebookEditor(notebook: $0) }
        .onAppear { handleNavigation() }
        .onChange(of: app.createNote) { handleNavigation() }
        .onChange(of: app.selectedNoteID) { handleNavigation() }
        .alert("Delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let deleting { if selectedID == deleting.id { selectedID = nil }; context.delete(deleting); app.save(context) }
                deleting = nil
            }
        } message: { Text("This removes the note permanently. Linked notes keep their original text.") }
    }
    private func handleNavigation() {
        if app.createNote { app.createNote = false; addNote() }
        if let id = app.selectedNoteID { selectedID = id; notebookID = nil; subjectID = nil; search = ""; app.selectedNoteID = nil }
    }
    private func addNote() {
        let note = Note(NoteRecord(notebookID: notebookID, subjectID: subjectID ?? notebooks.first { $0.id == notebookID }?.subjectID))
        context.insert(note)
        if app.save(context) { search = ""; selectedID = note.id }
    }
}

struct NoteEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Bindable var note: Note
    let notebooks: [Notebook]
    let subjects: [Subject]
    let allNotes: [Note]
    let openNote: (UUID) -> Void
    @State private var preview = false
    @State private var copiedMarkdown = false
    @State private var flashcards = false
    @State private var tags = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var saved = true
    private var outgoing: [Note] {
        let names = NoteLinks.titles(in: note.body)
        return allNotes.filter { candidate in candidate.id != note.id && names.contains { $0.caseInsensitiveCompare(candidate.title) == .orderedSame } }
    }
    private var incoming: [Note] {
        allNotes.filter { candidate in candidate.id != note.id && NoteLinks.titles(in: candidate.body).contains { $0.caseInsensitiveCompare(note.title) == .orderedSame } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(saved ? "Saved on this Mac" : "Saving…", systemImage: saved ? "checkmark.icloud" : "ellipsis").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Make flashcards", systemImage: "rectangle.on.rectangle") { flashcards = true }
                Picker("Mode", selection: $preview) { Text("Write").tag(false); Text("Preview").tag(true) }.pickerStyle(.segmented).frame(width: 160)
            }
            TextField("Untitled note", text: $note.title).textFieldStyle(.plain).font(.system(size: 28, weight: .bold, design: .rounded))
            HStack {
                Picker("Notebook", selection: $note.notebookID) { Text("Unfiled").tag(nil as UUID?); ForEach(notebooks) { Text($0.title).tag(Optional($0.id)) } }
                SubjectPicker(subjects: subjects, selection: $note.subjectID)
            }.font(.caption)
            TextField("Tags, separated by commas", text: $tags).textFieldStyle(.roundedBorder).font(.caption)
            Divider()
            if preview {
                ScrollView { MarkdownPreview(source: note.body).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
            } else {
                TextEditor(text: $note.body).font(.system(size: 14, design: .monospaced)).scrollContentBackground(.hidden).lineSpacing(6).accessibilityLabel("Markdown note content")
            }
            if !outgoing.isEmpty || !incoming.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack {
                        if !outgoing.isEmpty { Text("LINKS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                        ForEach(outgoing) { linked in Button(linked.title) { openNote(linked.id) }.font(.caption) }
                        if !incoming.isEmpty { Text("LINKED FROM").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                        ForEach(incoming) { linked in Button(linked.title) { openNote(linked.id) }.font(.caption) }
                    }
                }
            }
            HStack {
                Text("\(note.body.split { $0.isWhitespace || $0.isNewline }.count) words").font(.caption).foregroundStyle(.secondary)
                Button(copiedMarkdown ? "Copied" : "Copy Markdown", systemImage: copiedMarkdown ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(note.body, forType: .string) { copiedMarkdown = true }
                    else { app.error = "The note could not be copied to the clipboard. Please try again." }
                }
                .font(.caption)
                .disabled(note.body.isEmpty)
                .help("Copy this note’s Markdown source to the clipboard")
                Spacer()
                Text("Markdown · [[note links]] · Unicode math: x², √, ∑").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }.padding(28).background(.background)
            .sheet(isPresented: $flashcards) { NoteFlashcardsView(title: note.title, source: note.body, subjectID: note.subjectID ?? notebooks.first { $0.id == note.notebookID }?.subjectID) }
            .task(id: copiedMarkdown) {
                guard copiedMarkdown else { return }
                do { try await Task.sleep(for: .seconds(2)); copiedMarkdown = false } catch { }
            }
            .onAppear { tags = note.tags.joined(separator: ", ") }
            .onChange(of: note.title) { scheduleSave() }
            .onChange(of: note.body) { scheduleSave() }
            .onChange(of: note.notebookID) { scheduleSave() }
            .onChange(of: note.subjectID) { scheduleSave() }
            .onChange(of: tags) {
                let parsed = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
                if parsed != note.tags { note.tags = parsed; scheduleSave() }
            }
            .onDisappear { saveTask?.cancel(); if !note.isDeleted { saveNow() } }
    }
    private func scheduleSave() {
        saved = false; note.updatedAt = Date(); saveTask?.cancel()
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(400)); saveNow() } catch { }
        }
    }
    private func saveNow() {
        guard !note.isDeleted else { return }
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { note.title = "Untitled note" }
        saved = app.save(context, updateReminders: false)
    }
}
struct MarkdownPreview: View {
    let source: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(source.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("### ") { rich(String(line.dropFirst(4))).font(.headline).padding(.top, 10) }
                else if line.hasPrefix("## ") { rich(String(line.dropFirst(3))).font(.title2.bold()).padding(.top, 12) }
                else if line.hasPrefix("# ") { rich(String(line.dropFirst(2))).font(.title.bold()).padding(.top, 16) }
                else if line.hasPrefix("> ") { rich(String(line.dropFirst(2))).italic().foregroundStyle(.secondary).padding(.leading, 16) }
                else if line.hasPrefix("- ") || line.hasPrefix("* ") { HStack(alignment: .top) { Text("•"); rich(String(line.dropFirst(2))) } }
                else if line == "---" { Divider() }
                else if line.isEmpty { Spacer().frame(height: 5) }
                else { rich(line).font(.body) }
            }
        }.textSelection(.enabled)
    }
    private func rich(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
}
struct NotebookEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    let notebook: Notebook?
    @State private var title: String
    @State private var subjectID: UUID?
    init(notebook: Notebook? = nil) { self.notebook = notebook; _title = State(initialValue: notebook?.title ?? ""); _subjectID = State(initialValue: notebook?.subjectID) }
    var body: some View {
        VStack(spacing: 0) {
            Text(notebook == nil ? "New notebook" : "Edit notebook").font(.title2.bold()).padding(24)
            Form { TextField("Name", text: $title); SubjectPicker(subjects: subjects, selection: $subjectID, emptyLabel: "All subjects") }.formStyle(.grouped)
            SheetActions(title: "Save notebook", disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }) {
                if let notebook { notebook.title = title.trimmingCharacters(in: .whitespacesAndNewlines); notebook.subjectID = subjectID }
                else { context.insert(Notebook(NotebookRecord(title: title.trimmingCharacters(in: .whitespacesAndNewlines), subjectID: subjectID))) }
                if app.save(context) { dismiss() }
            }
        }.frame(width: 460, height: 280)
    }
}
