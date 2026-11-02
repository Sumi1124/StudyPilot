import SwiftUI
import StudyPilotData
import StudyPilotCore

struct CodexExtensionView: View {
    @Environment(CodexExtensionService.self) private var codex
    @LiveQuery(sort: \Note.title) private var notes: [Note]
    @AppStorage("codexExtensionEnabled") private var enabled = false
    @State private var draft = ""
    @State private var selectedNoteIDs: Set<UUID> = []
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var reviewingApproval: CodexToolApproval?

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
                        ForEach(codex.approvals) { approval in
                            HStack {
                                Label(approval.title, systemImage: "hand.raised").font(.callout.weight(.semibold))
                                Text(approval.fileName).font(.caption).lineLimit(1)
                                Spacer()
                                Button("Review") { reviewingApproval = approval }.buttonStyle(.borderedProminent)
                                Button("Reject") { Task { await codex.resolveApproval(approval, approve: false) } }
                            }.padding(10).background(Color.pilot.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
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
                        DisclosureGroup("Shared files (\(selectedFileIDs.count) selected)") {
                            Text("Choose files, check the copies to share, then send your message. Each read or tool use asks for approval. Edits change the shared copy; use Save copy to export. Files are forgotten when you disconnect or turn Codex off; content already sent stays in the conversation.")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(codex.sharedFiles) { file in
                                        HStack {
                                            Toggle(file.name, isOn: Binding(get: { selectedFileIDs.contains(file.id) }, set: { selected in
                                                if selected { selectedFileIDs.insert(file.id) } else { selectedFileIDs.remove(file.id) }
                                            })).disabled(codex.isResponding)
                                            Spacer()
                                            Button("Save copy") { codex.exportStudyFile(file) }
                                            Button("Remove", role: .destructive) { codex.removeStudyFile(file.id); selectedFileIDs.remove(file.id) }
                                        }.disabled(codex.isBusy || codex.isResponding)
                                    }
                                }
                            }.frame(maxHeight: 120)
                            Button("Choose text files…", systemImage: "doc.badge.plus") { codex.importStudyFiles() }
                                .disabled(codex.isBusy || codex.isResponding)
                            Text("This connection: \(codex.approvedToolCount) approved · \(codex.rejectedToolCount) rejected. New conversations support study tools; older chats may need a new conversation.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.font(.callout)
                        HStack(alignment: .bottom) {
                            TextField("Ask Codex about your studies…", text: $draft, axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                                .onSubmit(send)
                            Button("Send", action: send).buttonStyle(.borderedProminent)
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || codex.isResponding || codex.isBusy)
                        }
                        Text("Local preview: study tools require approval. Shell commands, network tools and access to other files remain blocked.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
        }
        .task { if enabled { await codex.start() } }
        .onChange(of: enabled) { if enabled { Task { await codex.start() } } else { codex.stop() } }
        .onChange(of: codex.sharedFiles.map(\.id)) { selectedFileIDs.formIntersection(codex.sharedFiles.map(\.id)) }
        .onChange(of: codex.approvals.map(\.id)) {
            if let reviewingApproval, !codex.approvals.contains(where: { $0.id == reviewingApproval.id }) { self.reviewingApproval = nil }
        }
        .sheet(item: $reviewingApproval) { approval in
            CodexToolReview(approval: approval) { approve in
                reviewingApproval = nil
                Task { await codex.resolveApproval(approval, approve: approve) }
            }
        }
        .alert("Codex needs attention", isPresented: Binding(get: { codex.error != nil }, set: { if !$0 { codex.error = nil } })) {
            Button("OK") { codex.error = nil }
        } message: { Text(codex.error ?? "") }
    }

    private func send() {
        let prompt = draft
        draft = ""
        let material = notes.filter { selectedNoteIDs.contains($0.id) }.map { (title: $0.title, body: $0.body) }
        let fileIDs = selectedFileIDs
        Task { await codex.send(prompt, selectedNotes: material, selectedFileIDs: fileIDs) }
    }
}

private struct CodexToolReview: View {
    let approval: CodexToolApproval
    let decide: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(approval.title).font(.title2.weight(.semibold))
            Text(approval.fileName).font(.headline)
            Text(approval.replacement == nil
                 ? "Approve this tool once. Its result is sent to OpenAI in the current conversation. Reading a file sends its full text."
                 : "Review the complete proposed change. Approving edits only the private shared copy. Save copy exports it to a location you choose.")
                .foregroundStyle(.secondary)
            if let query = approval.query { Text("Search: " + query).textSelection(.enabled) }
            HStack(alignment: .top, spacing: 12) {
                preview(approval.replacement == nil ? "Shared text" : "Before", approval.before)
                if let replacement = approval.replacement { preview("After", replacement) }
            }
            Text("This approval applies to one request in this conversation and expires after two minutes.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reject", role: .cancel) { decide(false) }
                Spacer()
                Button(approval.replacement == nil ? "Approve once" : "Apply to shared copy") { decide(true) }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: approval.replacement == nil ? 600 : 850, height: 600)
    }
    private func preview(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption.weight(.semibold))
            ScrollView { Text(text.isEmpty ? "(Empty file)" : text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        }.frame(maxWidth: .infinity)
    }
}
