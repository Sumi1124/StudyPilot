import SwiftUI
import SwiftData
import AppKit
import StudyPilotCore
import StudyPilotData

struct StudyChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @Environment(StudyChatService.self) private var chat
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var draft = ""
    @State private var attachment = ""
    @State private var deleting = false
    @State private var showContext = false
    @State private var showModels = false
    @State private var showHistory = true
    @State private var copiedID: UUID?
    @State private var savedIDs: Set<UUID> = []
    private var attachedText: String {
        if let note = notes.first(where: { "note:\($0.id)" == attachment }) { return String("Note: \(note.title)\n\(note.body)".prefix(1800)) }
        if let task = assignments.first(where: { "assignment:\($0.id)" == attachment }) { return String("Assignment: \(task.title)\nDue: \(task.dueDate.formatted())\nStatus: \(task.status)\n\(task.details)\nChecklist: \(task.checklist.map(\.title).joined(separator: "; "))".prefix(1800)) }
        return ""
    }
    private var attachmentSource: StudyChatSource? {
        if let note = notes.first(where: { "note:\($0.id)" == attachment }) { return .init(id: attachment, title: note.title, detail: "Explicitly attached note excerpt", kind: "note", localID: note.id) }
        if let task = assignments.first(where: { "assignment:\($0.id)" == attachment }) { return .init(id: attachment, title: task.title, detail: "Explicitly attached assignment excerpt", kind: "assignment", localID: task.id, date: task.dueDate) }
        return nil
    }
    var body: some View {
        HStack(spacing: 0) {
            if showHistory { history.frame(width: 190); Divider() }
            VStack(spacing: 0) { header; Divider(); conversation; Divider(); composer }
        }
        .alert("Delete this conversation?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { chat.deleteSelected() }
        } message: { Text("This removes the saved messages from this Mac. It cannot be undone.") }
        .onAppear { consumeDraft() }
        .task { await chat.models.refresh() }
        .onChange(of: app.chatDraft) { consumeDraft() }
        .onChange(of: app.showingStudyPlanner) { if app.showingStudyPlanner { showContext = false } }
    }
    private var history: some View {
        @Bindable var chat = chat
        return VStack(alignment: .leading, spacing: 12) {
            Button("New chat", systemImage: "square.and.pencil") { chat.newChat() }.disabled(chat.generating)
            Text("CONVERSATIONS").font(.caption2.bold()).foregroundStyle(.secondary)
            List(selection: $chat.selectedID) {
                ForEach(chat.threads.sorted { $0.updatedAt > $1.updatedAt }) { thread in
                    VStack(alignment: .leading, spacing: 4) { Text(thread.title).lineLimit(2); Text(thread.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary) }.padding(.vertical, 5).tag(thread.id)
                }
            }.listStyle(.plain).disabled(chat.generating)
            Button("Delete chat…", systemImage: "trash", role: .destructive) { deleting = true }.disabled(chat.selected == nil || chat.generating)
        }.padding(14)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { showHistory.toggle() } label: { Image(systemName: "sidebar.left") }.help("Show or hide conversations")
                Label("Study assistant", systemImage: "sparkles").font(.title2.bold())
                Spacer()
                Button("Context & sources", systemImage: "slider.horizontal.3") { showContext.toggle() }.popover(isPresented: $showContext) { contextSettings }
                if !showHistory { Button("New chat", systemImage: "plus") { chat.newChat() }.disabled(chat.generating) }
            }
            HStack {
                Picker("Model", selection: Binding(get: { chat.models.choice }, set: { chat.selectModel($0) })) {
                    ForEach(ChatModelChoice.allCases) { Text($0.title).tag($0) }
                }.frame(maxWidth: 300).disabled(chat.generating)
                    .onChange(of: chat.models.choice) { Task { await chat.models.refresh() } }
                Button("Model setup") { showModels.toggle() }.popover(isPresented: $showModels) {
                    VStack(alignment: .leading, spacing: 16) { Text("AI model").font(.title3.bold()); AIModelSettings() }.padding(20).frame(width: 430)
                }
                Spacer()
            }
            if let reason = chat.unavailableReason { Text(reason + " Saved workspace answers are still available.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("Workspace facts come directly from saved records. AI explanations may need checking.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Due today") { draft = "What tasks are due today?" }
                Button("Overdue") { draft = "Which tasks are overdue?" }
                Button("My calendar") { draft = "What is on my calendar today?" }
            }.font(.caption).disabled(chat.generating)
        }.padding(20)
    }
    private var contextSettings: some View {
        @Bindable var chat = chat
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Context & sources").font(.title3.bold())
                Toggle("Use my study tasks and note titles", isOn: $chat.useStudyContext).toggleStyle(.checkbox).disabled(chat.generating)
                if let status = chat.contextStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                CalendarChatPanel()
                Divider()
                Text("Task lists, deadlines, and today's or tomorrow's calendar are answered from saved data. General explanations use your selected local model. Context cards show which saved items were provided, not independent proof of an AI explanation.").font(.caption).foregroundStyle(.secondary)
                if let reason = chat.unavailableReason { Text(reason + " Saved-data answers still work.").font(.caption).foregroundStyle(.orange) }
                Text("Conversations stay on this Mac and are separate from workspace JSON backups.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.frame(width: 550, height: 480)
    }
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if chat.selected?.messages.isEmpty != false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What would help you get started?").font(.title2.bold())
                            Text("Try “What math tasks do I have?” or “Move my next study block to tomorrow at 5pm.”").foregroundStyle(.secondary)
                            Text("You can also attach a note for explanations, feedback, or practice questions.").font(.callout).foregroundStyle(.secondary)
                        }.padding(.vertical, 25)
                    }
                    ForEach(chat.selected?.messages ?? []) { message in messageView(message) }
                    if let proposal = chat.calendar.pending, proposal.threadID == chat.selectedID { CalendarMovePreview(proposal: proposal) }
                    if chat.generating { HStack { ProgressView().controlSize(.small); Text("Replying with \(chat.models.choice.title)…").foregroundStyle(.secondary) } }
                    if let error = chat.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if !chat.generating && chat.selected?.messages.last?.role == "user" { Button("Retry reply", systemImage: "arrow.clockwise") { chat.retry() } }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }.onChange(of: chat.selected?.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.selectedID) { chat.calendar.pending = nil; proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.generating) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Attach", selection: $attachment) {
                    Text("No attachment").tag("")
                    ForEach(notes.prefix(50)) { Text("Note: \($0.title)").tag("note:\($0.id)") }
                    ForEach(assignments.filter { !$0.isDone }.prefix(50)) { Text("Task: \($0.title)").tag("assignment:\($0.id)") }
                }.disabled(chat.generating)
                if !attachedText.isEmpty { Text("1,800-character excerpt").font(.caption2).foregroundStyle(.secondary) }
            }
            TextField("Ask about a task, your schedule, or a topic…", text: $draft, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).disabled(chat.generating)
            HStack {
                Text("\(draft.count)/2,000 · ⌘Return to send").font(.caption2).foregroundStyle(draft.count > 2000 ? Color.red : .secondary)
                Spacer()
                if chat.generating { Button("Stop", systemImage: "stop.fill") { chat.stop() } }
                else {
                    Button("Send", systemImage: "arrow.up") { send() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000 || (chat.unavailableReason != nil && !chat.canAnswerFacts(draft)))
                }
            }
        }.padding(18)
    }
    private func consumeDraft() {
        if let text = app.chatDraft { draft = draft.isEmpty ? text : draft + "\n" + text; app.chatDraft = nil }
    }
    private func send() { if chat.send(draft, context: attachedText, attachmentSource: attachmentSource) { draft = ""; attachment = "" } }
    private func messageView(_ message: StudyChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(message.role == "user" ? "You" : message.answerKind == "workspace" ? "From your workspace" : "StudyPilot", systemImage: message.role == "user" ? "person.crop.circle" : message.answerKind == "workspace" ? "checkmark.seal" : "sparkles").font(.caption.bold()).foregroundStyle(message.role == "user" ? Color.secondary : .pilot)
                Spacer()
                Text(message.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.tertiary)
            }
            if message.role == "assistant" {
                Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)).lineSpacing(4).textSelection(.enabled)
            } else { Text(message.text).textSelection(.enabled) }
            if !message.context.isEmpty { DisclosureGroup("Attached material") { Text(message.context).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
            if let sources = message.sources, !sources.isEmpty { ChatSourcesView(sources: sources, factual: message.answerKind == "workspace") }
            if message.role == "assistant" {
                HStack {
                    Button(copiedID == message.id ? "Copied" : "Copy", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string); copiedID = message.id }
                    Button(savedIDs.contains(message.id) ? "Saved to Notes" : "Save to Notes", systemImage: "note.text.badge.plus") {
                        context.insert(Note(NoteRecord(title: String((chat.selected?.title ?? "Study chat").prefix(100)), body: message.text)))
                        if app.save(context) { savedIDs.insert(message.id) }
                    }.disabled(savedIDs.contains(message.id))
                    if message.answerKind == "ai" { Text(message.model.map { "\($0) · AI generated" } ?? "AI generated").font(.caption2).foregroundStyle(.tertiary) }
                }.font(.caption)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(message.role == "user" ? Color.pilot.opacity(0.08) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
    }
}
struct ChatSourcesView: View {
    @Environment(AppState.self) private var app
    let sources: [StudyChatSource]
    let factual: Bool
    var body: some View {
        DisclosureGroup("\(factual ? "Saved records" : "Context provided") · \(sources.count)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sources.prefix(24)) { source in
                    Button {
                        if source.kind == "assignment", let id = source.localID { app.selectedAssignmentID = id; app.section = .assignments }
                        else if source.kind == "note", let id = source.localID { app.selectedNoteID = id; app.section = .notes }
                        else { app.openCalendar(source.date ?? app.now) }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: source.kind == "note" ? "note.text" : source.kind == "assignment" ? "checklist" : "calendar")
                            VStack(alignment: .leading, spacing: 3) { Text(source.title).font(.caption.bold()); Text(source.detail).font(.caption2).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "arrow.up.right").font(.caption2)
                        }.padding(9).background(Color.pilot.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 8)
        }.font(.caption).foregroundStyle(Color.pilot)
    }
}
