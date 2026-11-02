import SwiftUI
import StudyPilotData

struct CodexExtensionView: View {
    @Environment(CodexExtensionService.self) private var codex
    @LiveQuery(sort: \Note.title) private var notes: [Note]
    @AppStorage("codexExtensionEnabled") private var enabled = false
    @State private var draft = ""
    @State private var selectedNoteIDs: Set<UUID> = []

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                Label("Codex", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)
                Text("Optional extension").font(.caption).foregroundStyle(.secondary)
                Divider()
                if enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MODEL FOR NEW CHATS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Model for new chats", selection: Binding(
                            get: { codex.selectedModelID },
                            set: { codex.chooseModel($0) })) {
                                Text("Codex default").tag(nil as String?)
                                ForEach(codex.models) { model in
                                    Text(model.name).tag(Optional(model.id))
                                }
                            }.labelsHidden().frame(maxWidth: .infinity)
                        if let selected = codex.models.first(where: { $0.id == codex.selectedModelID }),
                           !selected.detail.isEmpty {
                            Text(selected.detail).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(3)
                        } else {
                            Text("Existing conversations keep their model.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if codex.models.isEmpty {
                            Button("Retry model list") { Task { await codex.start(); try? await codex.refreshModels() } }
                                .font(.caption)
                        }
                    }
                    Divider()
                }
                if codex.connected {
                    Button("New conversation", systemImage: "plus") { Task { await codex.newConversation() } }
                        .buttonStyle(.borderedProminent).disabled(codex.isBusy || codex.isResponding || codex.isBusy)
                    if let activeModelID = codex.activeModelID {
                        Text("Current chat: \(codex.models.first(where: { $0.id == activeModelID })?.name ?? activeModelID)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text("Conversations").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(codex.conversations) { conversation in
                                Button { Task { await codex.openConversation(conversation) } } label: {
                                    Text(conversation.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(codex.activeThreadID == conversation.id ? Color.pilot.opacity(0.12) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).disabled(codex.isBusy || codex.isResponding || codex.isBusy)
                            }
                        }
                    }
                } else { Text("Your conversations appear here after you connect.").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if codex.connected {
                    Text(codex.accountLabel ?? "ChatGPT connected").font(.caption).lineLimit(1)
                    Button("Disconnect and erase Codex data", role: .destructive) { Task { await codex.disconnect() } }
                        .font(.caption)
                }
            }.frame(width: 205).padding(18).background(Color.pilot.opacity(0.035))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    PageHeading(eyebrow: "EXTENSIONS", title: "Codex", subtitle: "Chat about selected notes with your own ChatGPT account.")
                    Text(codex.status).font(.caption).foregroundStyle(.secondary)
                }.padding(24)
                Divider()
                if !enabled {
                    EmptyState(symbol: "power", title: "Codex is off", message: "Enable it in Settings when you want to use it.")
                } else if !codex.connected {
                    VStack(spacing: 18) {
                        Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 38)).foregroundStyle(Color.pilot)
                        Text("Connect your ChatGPT account").font(.title2.weight(.semibold))
                        Text("Codex uses your own sign-in. Messages and notes you select are sent to OpenAI. StudyPilot never asks for or displays your password or token.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
                        Button("Connect with ChatGPT") { Task { await codex.signIn() } }.buttonStyle(.borderedProminent)
                        Button("Reconnect") { Task { await codex.start() } }.buttonStyle(.borderless)
                        Button("Check sign-in status") {
                            Task { try? await codex.refreshAccount(); try? await codex.refreshHistory() }
                        }.buttonStyle(.borderless)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                if codex.lines.isEmpty {
                                    EmptyState(symbol: "bubble.left.and.text.bubble.right", title: "Start a conversation",
                                               message: "Choose notes below if you want Codex to use them. Your other StudyPilot data is not added to the message.")
                                }
                                ForEach(codex.lines) { line in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(line.role).font(.caption.weight(.semibold)).foregroundStyle(Color.pilot)
                                        Text(line.text.isEmpty && codex.isResponding ? "Thinking…" : line.text)
                                            .textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, alignment: .leading).pilotCard().id(line.id)
                                }
                            }.padding(24)
                        }.onChange(of: codex.lines.count) {
                            if let id = codex.lines.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup("Share selected notes (\(selectedNoteIDs.count))") {
                            Text("Only checked note text is sent to OpenAI in your next message and saved in that Codex conversation. Up to five notes, 20,000 characters each.")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                VStack(alignment: .leading) {
                                    ForEach(notes) { note in
                                        Toggle(note.title, isOn: Binding(
                                            get: { selectedNoteIDs.contains(note.id) },
                                            set: { selected in
                                                if selected && selectedNoteIDs.count < 5 { selectedNoteIDs.insert(note.id) }
                                                if !selected { selectedNoteIDs.remove(note.id) }
                                            }))
                                    }
                                }
                            }.frame(maxHeight: 120)
                        }.font(.callout)
                        HStack(alignment: .bottom) {
                            TextField("Ask Codex about your studies…", text: $draft, axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                                .onSubmit(send)
                            Button("Send", action: send).buttonStyle(.borderedProminent)
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || codex.isResponding || codex.isBusy)
                        }
                        Text("Local preview: Codex tools and file changes are denied. Select notes explicitly before sending.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
        }
        .task { if enabled { await codex.start() } }
        .onChange(of: enabled) { if enabled { Task { await codex.start() } } else { codex.stop() } }
        .alert("Codex needs attention", isPresented: Binding(get: { codex.error != nil }, set: { if !$0 { codex.error = nil } })) {
            Button("OK") { codex.error = nil }
        } message: { Text(codex.error ?? "") }
    }

    private func send() {
        let prompt = draft
        draft = ""
        let material = notes.filter { selectedNoteIDs.contains($0.id) }.map { (title: $0.title, body: $0.body) }
        Task { await codex.send(prompt, selectedNotes: material) }
    }
}
