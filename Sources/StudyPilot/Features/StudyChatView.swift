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
    @State private var copiedID: UUID?
    @State private var savedIDs: Set<UUID> = []
    private var attachedText: String {
        if attachment.hasPrefix("note:"), let note = notes.first(where: { "note:\($0.id)" == attachment }) {
            return String("Note: \(note.title)\n\(note.body)".prefix(1800))
        }
        if attachment.hasPrefix("assignment:"), let item = assignments.first(where: { "assignment:\($0.id)" == attachment }) {
            return String("Assignment: \(item.title)\nDue: \(item.dueDate.formatted())\nStatus: \(item.status)\n\(item.details)\nChecklist: \(item.checklist.map(\.title).joined(separator: "; "))".prefix(1800))
        }
        return ""
    }
    var body: some View {
        @Bindable var chat = chat
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Button("New chat", systemImage: "square.and.pencil") { chat.newChat() }.disabled(chat.generating)
                Text("SAVED ON THIS MAC").font(.caption2.bold()).foregroundStyle(.secondary)
                List(selection: $chat.selectedID) {
                    ForEach(chat.threads.sorted { $0.updatedAt > $1.updatedAt }) { thread in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title).lineLimit(2)
                            Text(thread.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(thread.id)
                    }
                }.listStyle(.plain).disabled(chat.generating)
                Button("Delete chat…", systemImage: "trash", role: .destructive) { deleting = true }.disabled(chat.selected == nil || chat.generating)
            }.padding(18).frame(width: 200)
            Divider()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Label("AI Chat", systemImage: "bubble.left.and.bubble.right.fill").font(.title2.bold()); Spacer(); Text("On this Mac").font(.caption).foregroundStyle(Color.pilot) }
                    Text("Ask for explanations, hints, feedback, or a study plan. Attach a note or assignment when you want help with it.").font(.callout).foregroundStyle(.secondary)
                    Text("Chat history is saved locally, separately from workspace JSON backups. AI can make mistakes; check important details.").font(.caption).foregroundStyle(.secondary)
                    if let reason = chat.unavailableReason { Label(reason, systemImage: "info.circle").font(.callout).foregroundStyle(.orange) }
                }.padding(24)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if chat.selected?.messages.isEmpty != false {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("What would you like to work on?").font(.title3.bold())
                                    ForEach(["Explain a topic step by step", "Quiz me on my attached note", "Help me break down this assignment"], id: \.self) { prompt in
                                        Button(prompt, systemImage: "sparkles") { draft = prompt }
                                    }
                                }.padding(.vertical, 30)
                            }
                            ForEach(chat.selected?.messages ?? []) { message in messageView(message) }
                            if chat.generating { HStack { ProgressView().controlSize(.small); Text("Thinking on your Mac…").foregroundStyle(.secondary) } }
                            if let error = chat.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                            if !chat.generating && chat.selected?.messages.last?.role == "user" { Button("Retry reply", systemImage: "arrow.clockwise") { chat.retry() } }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }.onChange(of: chat.selected?.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                        .onChange(of: chat.selectedID) { proxy.scrollTo("bottom", anchor: .bottom) }
                        .onChange(of: chat.generating) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Attach", selection: $attachment) {
                        Text("No attachment").tag("")
                        ForEach(notes.prefix(50)) { Text("Note: \($0.title)").tag("note:\($0.id)") }
                        ForEach(assignments.filter { !$0.isDone }.prefix(50)) { Text("Assignment: \($0.title)").tag("assignment:\($0.id)") }
                    }.disabled(chat.generating)
                    if !attachedText.isEmpty { Text("Only this item’s first 1,800 characters will be included with your next message.").font(.caption).foregroundStyle(.secondary) }
                    TextField("Ask your study companion…", text: $draft, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder).disabled(chat.generating)
                    HStack {
                        Text("\(draft.count)/2,000 characters").font(.caption).foregroundStyle(draft.count > 2000 ? .red : .secondary)
                        Spacer()
                        if chat.generating { Button("Stop", systemImage: "stop.fill") { chat.stop() } }
                        else { Button("Send", systemImage: "arrow.up") { send() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000 || chat.unavailableReason != nil) }
                    }
                }.padding(20)
            }.frame(maxWidth: .infinity)
        }
        .alert("Delete this conversation?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { chat.deleteSelected() }
        } message: { Text("This removes the saved messages from this Mac. It cannot be undone.") }
    }
    private func send() { if chat.send(draft, context: attachedText) { draft = ""; attachment = "" } }
    private func messageView(_ message: StudyChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message.role == "user" ? "You" : "StudyPilot", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles").font(.caption.bold()).foregroundStyle(message.role == "user" ? Color.secondary : Color.pilot)
            Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if !message.context.isEmpty { DisclosureGroup("Attached study material") { Text(message.context).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
            if message.role == "assistant" {
                HStack {
                    Button(copiedID == message.id ? "Copied" : "Copy", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string); copiedID = message.id }
                    Button(savedIDs.contains(message.id) ? "Saved to Notes" : "Save to Notes", systemImage: "note.text.badge.plus") {
                        context.insert(Note(NoteRecord(title: String((chat.selected?.title ?? "AI study chat").prefix(100)), body: message.text)))
                        if app.save(context) { savedIDs.insert(message.id) }
                    }.disabled(savedIDs.contains(message.id))
                }.font(.caption)
            }
        }.padding(16).background(message.role == "user" ? Color.pilot.opacity(0.08) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
    }
}
