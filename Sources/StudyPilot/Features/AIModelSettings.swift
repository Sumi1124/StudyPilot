import SwiftUI
import StudyPilotCore

struct AIModelSettings: View {
    @Environment(StudyChatService.self) private var chat
    @Environment(CodexExtensionService.self) private var codex
    @AppStorage("codexExtensionEnabled") private var codexEnabled = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("AI provider", selection: Binding(get: { chat.models.choice }, set: { chat.selectModel($0) })) {
                ForEach(ChatModelChoice.allCases) { Text($0.title).tag($0) }
            }.disabled(chat.generating)
            Text("Choose the provider for study chat, time estimates, planning advice and notebook questions. Apple Intelligence and Qwen run on this Mac. Codex uses your ChatGPT account online.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if chat.models.choice == .codex {
                Divider()
                Label("Codex · separate from memory", systemImage: "brain") .font(.headline)
                Text("Each request starts fresh. Earlier chats and saved memory are not sent. Chat calendar and study context start off; enable them only when you want to share those details. Estimates, planning advice and notebook questions send the inputs shown in that feature to OpenAI.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Enable Codex connection", isOn: $codexEnabled)
                Text(codex.connected ? "Connected to your ChatGPT account" : codex.status).font(.caption).foregroundStyle(.secondary)
                if !codex.connected {
                    Button("Connect with ChatGPT") { Task { await codex.signIn() } }
                        .disabled(!codexEnabled || codex.isBusy)
                }
                Picker("Codex model", selection: Binding(get: { codex.selectedModelID ?? "" }, set: { codex.chooseModel($0.isEmpty ? nil : $0) })) {
                    Text("Codex default").tag("")
                    ForEach(codex.models) { Text($0.name).tag($0.id) }
                }.disabled(!codex.connected || codex.isBusy || codex.isResponding)
                if let error = codex.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Divider()
            Text("Qwen 3.5 · 0.8B").font(.headline)
            Text(chat.models.status).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if chat.models.downloading {
                if let fraction = chat.models.fraction { ProgressView(value: fraction).accessibilityLabel("Model download") }
                else { ProgressView().controlSize(.small) }
                Button("Stop download") { chat.models.cancelDownload() }
            } else {
                HStack {
                    Button(chat.models.checking ? "Checking…" : "Check local service") { Task { await chat.models.refresh() } }.disabled(chat.models.checking)
                    if !chat.models.ready {
                        Button("Download 0.8B model") { chat.models.download() }.disabled(chat.models.checking)
                    } else { Label("Installed", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                }.disabled(chat.generating)
            }
            Text("Download fetches Qwen here in StudyPilot. If the local engine is missing or too old, StudyPilot downloads a verified copy first. The model needs about 1 GB of storage and remains optional.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if chat.models.choice == .qwen08 && !chat.models.ready {
                Text("Saved workspace answers still work while the model is unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }.task {
            chat.models.codex = codex
            if chat.models.choice == .codex && codexEnabled { await codex.start() }
            await chat.models.refresh()
        }
            .onChange(of: chat.models.choice) { Task { await chat.models.refresh() } }
    }
}
