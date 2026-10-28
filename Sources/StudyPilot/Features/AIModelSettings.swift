import SwiftUI
import StudyPilotCore

struct AIModelSettings: View {
    @Environment(StudyChatService.self) private var chat
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Chat model", selection: Binding(get: { chat.models.choice }, set: { chat.selectModel($0) })) {
                ForEach(ChatModelChoice.allCases) { Text($0.title).tag($0) }
            }.disabled(chat.generating)
            Text("Apple Intelligence uses macOS’s model. Qwen 3.5 0.8B runs through Ollama on this Mac. A smaller model uses less memory, but its explanations and proposals can be less reliable.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Qwen 3.5 · 0.8B").font(.headline)
            Text(chat.models.status).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if chat.models.downloading {
                if let fraction = chat.models.fraction { ProgressView(value: fraction).accessibilityLabel("Model download") }
                else { ProgressView().controlSize(.small) }
                Button("Stop download") { chat.models.cancelDownload() }
            } else {
                HStack {
                    Button(chat.models.checking ? "Checking…" : "Check Ollama") { Task { await chat.models.refresh() } }.disabled(chat.models.checking)
                    if !chat.models.ready {
                        Button("Download 0.8B model") { chat.models.download() }.disabled(!chat.models.reachable || chat.models.checking)
                    } else { Label("Installed", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                }.disabled(chat.generating)
            }
            Link("Install or update Ollama…", destination: URL(string: "https://ollama.com/download")!).font(.caption)
            Text("Optional: start Ollama before using Qwen. Download only if you want this model. The first download needs internet and roughly 1 GB of storage; afterward chat runs locally. StudyPilot connects only to 127.0.0.1:11434 and never switches models automatically.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if chat.models.choice == .qwen08 && !chat.models.ready {
                Text("Saved workspace answers still work while the model is unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }.task { await chat.models.refresh() }
            .onChange(of: chat.models.choice) { Task { await chat.models.refresh() } }
    }
}
