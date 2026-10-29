import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers
import StudyPilotCore
import StudyPilotData

struct NotebooksView: View {
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Notebook.title) private var notebooks: [Notebook]
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var search = ""
    @State private var newNotebook = false
    private var filtered: [Notebook] { notebooks.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || subjectName($0).localizedCaseInsensitiveContains(search) } }
    private func subjectName(_ notebook: Notebook) -> String { subjects.first { $0.id == notebook.subjectID }?.name ?? "" }
    var body: some View {
        Group {
            if let notebook = notebooks.first(where: { $0.id == app.selectedNotebookID }) {
                NotebookWorkspace(notebook: notebook).id(notebook.id)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Notebooks").font(.system(size: 30, weight: .semibold))
                                Text("A place for your sources, questions, and study notes.").font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("New notebook", systemImage: "plus") { newNotebook = true }.buttonStyle(.borderedProminent)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find a notebook or subject", text: $search).textFieldStyle(.plain)
                            Text("\(notebooks.count) notebooks").font(.caption).foregroundStyle(.secondary)
                        }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
                        if notebooks.isEmpty {
                            VStack(spacing: 18) {
                                Image(systemName: "books.vertical").font(.system(size: 44, weight: .light)).foregroundStyle(Color.notebookInk)
                                Text("Start with what you're studying").font(.title2.weight(.medium))
                                Text("Create a notebook for a class or topic. Add reading material, keep your own notes, and return to the exact passages behind an answer.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                                Button("Create your first notebook") { newNotebook = true }.buttonStyle(.borderedProminent)
                            }.frame(maxWidth: .infinity).padding(.vertical, 70)
                        } else if filtered.isEmpty {
                            EmptyState(symbol: "magnifyingglass", title: "No matching notebooks", message: "Try another title or subject.")
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 18)], alignment: .leading, spacing: 18) {
                                ForEach(filtered) { notebook in notebookCard(notebook) }
                            }
                        }
                        HStack(alignment: .top, spacing: 24) {
                            notebookHint("Collect", symbol: "doc.badge.plus", text: "Bring PDF, text, or Markdown readings into one place.")
                            notebookHint("Understand", symbol: "text.magnifyingglass", text: "Search passages or ask questions with source references.")
                            notebookHint("Remember", symbol: "rectangle.on.rectangle", text: "Write your own notes and make revision cards.")
                        }.padding(.top, 12)
                    }.padding(30).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
        }.sheet(isPresented: $newNotebook) { NotebookEditor() }
    }
    private func notebookHint(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.callout.weight(.medium))
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func notebookCard(_ notebook: Notebook) -> some View {
        let items = notes.filter { $0.notebookID == notebook.id }
        let sources = items.filter { $0.tags.contains(NotebookResearch.sourceTag) }.count
        let subject = subjects.first { $0.id == notebook.subjectID }
        return Button { app.selectedNotebookID = notebook.id } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "book.closed").font(.system(size: 23, weight: .regular)).foregroundStyle(subject?.color ?? .notebookInk)
                        .frame(width: 48, height: 48).background((subject?.color ?? .notebookInk).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.callout).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(notebook.title).font(.system(size: 18, weight: .semibold)).lineLimit(2).frame(height: 44, alignment: .topLeading)
                    SubjectBadge(subject: subject)
                }
                Divider()
                HStack {
                    Text("\(sources) sources · \(items.count - sources) notes")
                    Spacer()
                    if let updated = items.first?.updatedAt { Text(updated, format: .dateTime.month(.abbreviated).day()) }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(subject?.color ?? .notebookInk).frame(width: 3).padding(.vertical, 24) }
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel("Open \(notebook.title), \(sources) sources, \(items.count - sources) notes")
    }
}

private enum NotebookTab: String, CaseIterable { case ask = "Ask sources", read = "Read", notes = "Notes" }

private struct NotebookWorkspace: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(StudyChatService.self) private var chat
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    let notebook: Notebook
    @State private var tab = NotebookTab.ask
    @State private var included: Set<UUID> = []
    @State private var initialized = false
    @State private var readingID: UUID?
    @State private var passage: NotebookPassage?
    @State private var matches: [NotebookPassage] = []
    @State private var sourceSearch = ""
    @State private var question = ""
    @State private var controller = NotebookResearchController()
    @State private var importer = false
    @State private var importing = false
    @State private var pasteSource = false
    @State private var existingNote = false
    @State private var editingNotebook = false
    @State private var deleting: Note?
    @State private var flashcards: Note?
    @State private var savedAnswer = false
    @State private var error: String?
    private var notes: [Note] { allNotes.filter { $0.notebookID == notebook.id && !$0.tags.contains(NotebookResearch.sourceTag) } }
    private var sources: [Note] { allNotes.filter { $0.notebookID == notebook.id && $0.tags.contains(NotebookResearch.sourceTag) }.sorted { $0.createdAt < $1.createdAt } }
    private var selected: [NoteRecord] { sources.filter { included.contains($0.id) }.map(\.record) }
    private var reading: Note? { sources.first { $0.id == readingID } }
    private var visibleSources: [Note] { sources.filter { sourceSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(sourceSearch) } }
    private var excerptContext: [NotebookPassage] { NotebookResearch.context(question: question, sources: selected) }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    sourceRail.frame(width: geometry.size.width >= 1000 ? 230 : 210)
                    Divider()
                    VStack(spacing: 0) {
                        Picker("Notebook view", selection: $tab) { ForEach(NotebookTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 350).padding(16)
                        Divider()
                        Group {
                            switch tab { case .ask: questionArea; case .read: reader; case .notes: notesArea }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.background(Color(nsColor: .textBackgroundColor))
                    if geometry.size.width >= 1000 { Divider(); studio.frame(width: 220) }
                }
            }
        }
        .sheet(isPresented: $pasteSource) { PastedNotebookSource(notebook: notebook) { id in included.insert(id); readingID = id; tab = .read } }
        .sheet(isPresented: $existingNote) { ExistingNotebookSource(notebook: notebook) { id in included.insert(id); readingID = id; tab = .read } }
        .sheet(isPresented: $editingNotebook) { NotebookEditor(notebook: notebook) }
        .sheet(item: $flashcards) { NoteFlashcardsView(title: $0.title, source: $0.body, subjectID: notebook.subjectID) }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText], allowsMultipleSelection: false) { result in
            switch result { case .success(let urls): if let url = urls.first { importSource(url) }; case .failure(let failure): error = failure.localizedDescription }
        }
        .alert("Remove source?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Remove", role: .destructive) { if let deleting { removeSource(deleting) }; deleting = nil }
        } message: { Text("This deletes the imported text copy from StudyPilot. Your original file or note is kept.") }
        .alert("Notebook needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .onChange(of: sources.map(\.id), initial: true) { _, ids in
            if !initialized && !allNotes.isEmpty { included = Set(ids); initialized = true }
            included.formIntersection(ids)
            if readingID == nil { readingID = ids.first }
        }
        .onChange(of: selected) { controller.invalidate(); savedAnswer = false; passage = nil; matches = [] }
        .onChange(of: question) { controller.invalidate(); savedAnswer = false }
        .onChange(of: chat.models.choice) { controller.invalidate(); savedAnswer = false }
        .task { if chat.models.choice == .qwen08 { await chat.models.refresh() } }
        .onDisappear { controller.cancel() }
    }
    private var header: some View {
        HStack(spacing: 14) {
            Button { app.selectedNotebookID = nil } label: { Image(systemName: "chevron.left") }.help("All notebooks")
            VStack(alignment: .leading, spacing: 3) {
                Text(notebook.title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text("\(sources.count) sources · \(notes.count) notes · stored on this Mac").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Study tools", systemImage: "rectangle.grid.1x2") {
                Button("Write a note", action: newNote)
                Button("Make flashcards from open source") { flashcards = reading }.disabled(reading == nil)
                Button("Open revision") { app.section = .revision }
                Divider()
                Button("Edit notebook") { editingNotebook = true }
            }.fixedSize()
        }.padding(.horizontal, 20).padding(.vertical, 18)
    }
    private var sourceRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Sources").font(.headline); Spacer(); Text("\(included.count)/\(sources.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            Menu { Button("Import file…") { importer = true }; Button("Paste text…") { pasteSource = true }; Button("Add an existing note…") { existingNote = true } } label: {
                Label("Add source", systemImage: "plus").frame(maxWidth: .infinity)
            }.menuStyle(.borderedButton).disabled(importing || sources.count >= 50)
            if importing { HStack { ProgressView().controlSize(.small); Text("Reading file…").font(.caption) } }
            if !sources.isEmpty {
                TextField("Find a source", text: $sourceSearch).textFieldStyle(.roundedBorder)
                HStack {
                    Button(included.count == sources.count ? "Deselect all" : "Select all") { included = included.count == sources.count ? [] : Set(sources.map(\.id)) }.buttonStyle(.link)
                    Spacer()
                    Text("Use in answers").foregroundStyle(.tertiary)
                }.font(.caption2)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) { Image(systemName: "doc.text").font(.title); Text("Your reading goes here").font(.callout.weight(.medium)); Text("Add a PDF, text file, or class note to start.").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 25)
                    }
                    ForEach(visibleSources) { source in
                        HStack(alignment: .top, spacing: 7) {
                            Toggle("Include \(source.title)", isOn: Binding(get: { included.contains(source.id) }, set: { if $0 { included.insert(source.id) } else { included.remove(source.id) } })).labelsHidden().toggleStyle(.checkbox)
                            Button { readingID = source.id; passage = nil; tab = .read } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(source.title).font(.callout.weight(.medium)).lineLimit(3).multilineTextAlignment(.leading)
                                    Text("\(source.body.split(whereSeparator: \.isWhitespace).count) words").font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Read \(source.title)")
                        }.padding(10).background(readingID == source.id && tab == .read ? Color.notebookInk.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contextMenu { Button("Remove source…", role: .destructive) { deleting = source } }
                    }
                }
            }
            Text("Only checked sources are used for questions. Files are stored as text copies.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxHeight: .infinity, alignment: .top)
    }
    private var questionArea: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let answer = controller.answer {
                        HStack { Label("Source answer", systemImage: "text.bubble").font(.headline); Spacer(); Text(controller.model?.title ?? "").font(.caption2).foregroundStyle(.secondary) }
                        Text(controller.input?.question ?? "").font(.title3.weight(.medium)).textSelection(.enabled)
                        Text(answer.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                        if !answer.citations.isEmpty {
                            Text("SOURCE PASSAGES").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                            ForEach(Array(answer.citations.enumerated()), id: \.element.id) { index, citation in
                                Button { open(citation) } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        HStack { Text("\(index + 1)").font(.caption.bold()).frame(width: 22, height: 22).background(Color.notebookInk.opacity(0.12), in: Circle()); Text(citation.title).font(.callout.weight(.medium)).lineLimit(1); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
                                        Text(citation.text).font(.caption).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading)
                                    }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Read original passage \(citation.number)")
                            }
                            Text("AI explanation from \(controller.input?.passages.count ?? 0) excerpts, not the whole notebook. Open the passages to check its interpretation.").font(.caption2).foregroundStyle(.secondary)
                            Button(savedAnswer ? "Saved to notebook notes" : "Save answer as a note", systemImage: savedAnswer ? "checkmark" : "note.text.badge.plus", action: saveAnswer).disabled(savedAnswer)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            Image(systemName: "text.book.closed").font(.system(size: 36, weight: .light)).foregroundStyle(Color.notebookInk)
                            Text("Work with your reading.").font(.system(size: 27, weight: .medium, design: .serif))
                            Text("Ask a question about your checked sources. Answers include the original passages so you can read them in context.").foregroundStyle(.secondary).lineSpacing(4)
                            if !selected.isEmpty {
                                Button("What are the main ideas in these excerpts?") { question = "What are the main ideas in these excerpts?" }.buttonStyle(.bordered)
                                Text("Or search for a key term below. Passage search works without AI.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 28)
                    }
                    if let error = controller.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(26).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
            }
            Divider()
            VStack(alignment: .leading, spacing: 11) {
                TextField("Ask about your sources…", text: $question, axis: .vertical).lineLimit(2...4).textFieldStyle(.plain).onSubmit(ask)
                HStack(spacing: 10) {
                    Text("\(included.count) sources · \(chat.models.choice.title)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Find passages", action: findPassages).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selected.isEmpty)
                    if controller.running { ProgressView().controlSize(.small); Button("Stop") { controller.cancel() } }
                    else { Button("Ask", systemImage: "arrow.up", action: ask).buttonStyle(.borderedProminent).disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 600 || selected.isEmpty || chat.unavailableReason != nil || chat.generating) }
                }
                if question.count > 600 { Text("Keep your question to 600 characters.").font(.caption2).foregroundStyle(.orange) }
                if let reason = chat.unavailableReason { Text(reason + " You can still find passages.").font(.caption2).foregroundStyle(.secondary) }
            }.padding(18).background(Color(nsColor: .controlBackgroundColor))
        }
    }
    private var reader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let reading {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) { Text(reading.title).font(.system(size: 26, weight: .semibold, design: .serif)); Text("Imported text · \(reading.body.split(whereSeparator: \.isWhitespace).count) words").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Menu { Button("Make flashcards") { flashcards = reading }; Button("Remove source…", role: .destructive) { deleting = reading } } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                        }
                        if let passage, passage.sourceID == reading.id {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Referenced passage \(passage.number)", systemImage: "quote.opening").font(.caption.weight(.medium))
                                    Spacer()
                                    if let index = matches.firstIndex(where: { $0.id == passage.id }) {
                                        Text("\(index + 1) of \(matches.count)").font(.caption2).foregroundStyle(.secondary)
                                        Button { open(matches[index - 1]) } label: { Image(systemName: "chevron.left") }.disabled(index == 0).help("Previous matching passage")
                                        Button { open(matches[index + 1]) } label: { Image(systemName: "chevron.right") }.disabled(index + 1 == matches.count).help("Next matching passage")
                                    }
                                }
                                Text(passage.text).font(.body).lineSpacing(5).textSelection(.enabled)
                            }
                                .padding(18).background(Color.notebookInk.opacity(0.09), in: RoundedRectangle(cornerRadius: 10)).id("citation")
                        }
                        Text(reading.body).font(.system(size: 15, design: .serif)).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else { EmptyState(symbol: "doc.text", title: "Select a source to read", message: "Choose a document from the source list, or add your first reading.") }
                }.padding(28).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }.onChange(of: passage?.id) { if passage != nil { proxy.scrollTo("citation", anchor: .top) } }
        }
    }
    private var notesArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("Notebook notes").font(.title3.weight(.semibold)); Spacer(); Button("New note", systemImage: "plus", action: newNote) }
                if notes.isEmpty { EmptyState(symbol: "square.and.pencil", title: "Make this notebook your own", message: "Write class notes, save an answer with its passages, or keep a short summary in your own words.") }
                ForEach(notes) { note in
                    Button { app.selectedNoteID = note.id; app.section = .notes } label: {
                        VStack(alignment: .leading, spacing: 9) { HStack { Image(systemName: "note.text").foregroundStyle(Color.notebookInk); Text(note.title).font(.headline).lineLimit(2); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.tertiary) }; Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(4).multilineTextAlignment(.leading); Text(note.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary) }.pilotCard().contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(24)
        }
    }
    private var studio: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Study tools").font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    tool("Write a note", detail: "Capture it in your words", symbol: "square.and.pencil", action: newNote)
                    tool("Make flashcards", detail: reading == nil ? "Open a source first" : "Use the open reading", symbol: "rectangle.on.rectangle") { flashcards = reading }.disabled(reading == nil)
                    tool("Review cards", detail: "Open your revision decks", symbol: "arrow.clockwise") { app.section = .revision }
                }
                Divider()
                HStack { Text("Notes").font(.callout.weight(.semibold)); Spacer(); Text("\(notes.count)").font(.caption).foregroundStyle(.secondary) }
                if notes.isEmpty { Text("Your saved notes will appear here.").font(.caption).foregroundStyle(.secondary) }
                ForEach(notes.prefix(5)) { note in
                    Button { app.selectedNoteID = note.id; app.section = .notes } label: { Label(note.title, systemImage: "note.text").font(.callout).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                }
                if notes.count > 5 { Button("View all notes") { tab = .notes }.buttonStyle(.link) }
                Divider()
                Label("Local workspace", systemImage: "internaldrive").font(.caption.weight(.medium))
                Text("Imported text and notebook notes are included in your StudyPilot backups.").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }
    }
    private func tool(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(alignment: .top, spacing: 10) { Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Color.notebookInk).frame(width: 22); VStack(alignment: .leading, spacing: 4) { Text(title).font(.callout.weight(.medium)); Text(detail).font(.caption2).foregroundStyle(.secondary) }; Spacer(minLength: 0) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
    private func ask() {
        guard !controller.running, chat.unavailableReason == nil, !chat.generating else { return }
        do { controller.start(input: try NotebookQuestion(question: question, passages: excerptContext), model: chat.models.choice, client: chat.models.client); savedAnswer = false }
        catch { self.error = error.localizedDescription }
    }
    private func findPassages() {
        matches = NotebookResearch.relevant(question: question, passages: selected.flatMap { NotebookResearch.passages(in: $0) })
        if let first = matches.first { open(first) }
        else { error = "No matching passages in your checked sources. Try a shorter key term or check another source." }
    }
    private func open(_ citation: NotebookPassage) { readingID = citation.sourceID; passage = citation; tab = .read }
    private func newNote() {
        do {
            let transaction = ModelContext(context.container); transaction.autosaveEnabled = false
            let note = Note(NoteRecord(notebookID: notebook.id, subjectID: notebook.subjectID)); transaction.insert(note); try transaction.save()
            app.selectedNoteID = note.id; app.section = .notes
        } catch { self.error = error.localizedDescription }
    }
    private func saveAnswer() {
        guard let answer = controller.answer, let input = controller.input, !answer.citations.isEmpty else { return }
        do {
            let body = "# " + input.question + "\n\n" + answer.text + "\n\nAI explanation · " + (controller.model?.title ?? "Local model") + " · Check against the passages below.\n\n" + answer.citations.map { "## " + $0.title + " — passage \($0.number)\n\n" + $0.text }.joined(separator: "\n\n")
            let transaction = ModelContext(context.container); transaction.autosaveEnabled = false
            transaction.insert(Note(NoteRecord(title: String(input.question.prefix(120)), body: body, notebookID: notebook.id, subjectID: notebook.subjectID, tags: [NotebookResearch.answerTag])))
            try transaction.save(); savedAnswer = true
        } catch { self.error = error.localizedDescription }
    }
    private func removeSource(_ source: Note) {
        do {
            let transaction = ModelContext(context.container); transaction.autosaveEnabled = false
            guard let copy = try transaction.fetch(FetchDescriptor<Note>()).first(where: { $0.id == source.id }) else { return }
            transaction.delete(copy); try transaction.save(); included.remove(source.id)
            if readingID == source.id { readingID = nil; passage = nil }
            controller.invalidate()
        } catch { self.error = error.localizedDescription }
    }
    private func importSource(_ url: URL) {
        guard !importing else { return }; importing = true
        Task {
            defer { importing = false }
            do {
                let value = try await Task.detached(priority: .userInitiated) { try NotebookSourceImport.read(url) }.value
                let id = try NotebookSourceStorage.save(title: value.title, text: value.text, notebook: notebook, container: context.container)
                included.insert(id); readingID = id; tab = .read
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor private enum NotebookSourceStorage {
    static func save(title: String, text: String, notebook: Notebook, container: ModelContainer) throws -> UUID {
        try NotebookResearch.validateSource(title: title, text: text)
        let transaction = ModelContext(container); transaction.autosaveEnabled = false
        let records = try transaction.fetch(FetchDescriptor<Note>()).filter { $0.notebookID == notebook.id && $0.tags.contains(NotebookResearch.sourceTag) }
        guard records.count < 50 else { throw PlanningError.invalid("A notebook can hold up to 50 imported sources.") }
        guard !records.contains(where: { $0.title == title && $0.body == text }) else { throw PlanningError.invalid("This source is already in the notebook.") }
        let note = Note(NoteRecord(title: title, body: text, notebookID: notebook.id, subjectID: notebook.subjectID, tags: [NotebookResearch.sourceTag]))
        transaction.insert(note); try transaction.save(); return note.id
    }
}

private struct PastedNotebookSource: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let notebook: Notebook
    let added: (UUID) -> Void
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a text source").font(.title2.weight(.semibold))
            Text("Paste class material or a reading excerpt. A text copy is saved in this notebook.").font(.callout).foregroundStyle(.secondary)
            TextField("Source title", text: $title).textFieldStyle(.roundedBorder)
            TextEditor(text: $text).font(.body).border(Color.secondary.opacity(0.2)).accessibilityLabel("Source text")
            Text("\(text.utf8.count.formatted()) / 200,000 bytes").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Add source") {
                do { let id = try NotebookSourceStorage.save(title: title.trimmingCharacters(in: .whitespacesAndNewlines), text: text, notebook: notebook, container: context.container); added(id); dismiss() }
                catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > NotebookResearch.maximumSourceBytes || title.count > 300) }
        }.padding(24).frame(width: 580, height: 530)
    }
}

private struct ExistingNotebookSource: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    let notebook: Notebook
    let added: (UUID) -> Void
    @State private var search = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Add an existing note").font(.title2.weight(.semibold)); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Adds a separate source copy. Later edits to the original note won't change it.").font(.callout).foregroundStyle(.secondary)
            TextField("Find a note", text: $search).textFieldStyle(.roundedBorder)
            List(notes.filter { !$0.tags.contains(NotebookResearch.sourceTag) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { note in
                Button {
                    do { let id = try NotebookSourceStorage.save(title: note.title, text: note.body, notebook: notebook, container: context.container); added(id); dismiss() }
                    catch { self.error = error.localizedDescription }
                } label: { VStack(alignment: .leading, spacing: 5) { Text(note.title).font(.headline); Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 6) }.buttonStyle(.plain)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width: 560, height: 500)
    }
}

extension Color {
    static var notebookInk: Color { .pilot }
}
