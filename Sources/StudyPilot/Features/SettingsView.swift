import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import StudyPilotCore
import StudyPilotData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @AppStorage("displayName") private var displayName = ""
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @State private var backups: [URL] = []
    @State private var candidate: BackupEnvelope?
    @State private var candidateName = ""
    @State private var message: String?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Make yourself at home").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(24)
            Form {
                Section("Your workspace") {
                    TextField("Preferred name", text: $displayName)
                    Picker("Appearance", selection: $appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }
                    Text("No account. No subscriptions. Your work stays on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
                Section("App updates") {
                    LabeledContent("Installed version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    AppUpdateButton()
                    Text("Download and install signed StudyPilot updates here. The app relaunches when installation is complete.").font(.caption).foregroundStyle(.secondary)
                    if focus.state != nil { Text("Finish the active focus session before updating.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("AI model") { AIModelSettings() }
                Section("Reminders") {
                    Toggle("Enable local reminders", isOn: Binding(get: { remindersEnabled }, set: { enabled in
                        if enabled { Task { await ReminderService.shared.requestPermission(context: context) } }
                        else { remindersEnabled = false; ReminderService.shared.cancelFocus(); Task { await ReminderService.shared.reconcile(context: context) } }
                    }))
                    Text(ReminderService.shared.status).font(.caption).foregroundStyle(.secondary)
                    if let error = ReminderService.shared.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("macOS controls delivery. A reminder may be quiet during Focus or Do Not Disturb. Reopen StudyPilot to refresh future reminders.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your data, in your hands") {
                    HStack {
                        Button("Export JSON…", systemImage: "square.and.arrow.up", action: export)
                        Button("Import / restore…", systemImage: "square.and.arrow.down", action: chooseImport).disabled(focus.state != nil)
                    }
                    Text("JSON includes all subjects, projects, assignments, notes, decks, reviews, study history, assessments and calendar events. Import replaces the workspace after confirmation; a safety backup is saved first.").font(.caption).foregroundStyle(.secondary)
                    if focus.state != nil { Text("Finish the active timer before restoring a workspace.").font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button("Create local backup") { perform { let url = try BackupService.create(context); message = "Backup saved: \(url.lastPathComponent)"; try refresh() } }
                        Button("Show backup folder") { perform { NSWorkspace.shared.open(try BackupService.directory(context)) } }
                    }
                    Text("An automatic backup is created on the first launch each day. Backups stay on this Mac and are never removed automatically. Export a copy elsewhere for protection against disk failure.").font(.caption).foregroundStyle(.secondary)
                    ForEach(backups.prefix(8), id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                            Spacer()
                            Button("Restore…") { prepare(url) }.disabled(focus.state != nil)
                        }
                    }
                }
                Section("Keyboard shortcuts") {
                    LabeledContent("New assignment", value: "⌘N")
                    LabeledContent("New note", value: "⇧⌘N")
                    LabeledContent("Search & quick actions", value: "⌘K")
                    LabeledContent("Start / open focus", value: "⇧⌘F")
                    LabeledContent("Navigate workspace sections", value: "⌘1–9")
                }
                if let message { Text(message).font(.caption).foregroundStyle(Color(hex: "2B998C")).textSelection(.enabled) }
                if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            }.formStyle(.grouped)
        }.frame(width: 670, height: 760)
            .onAppear { perform { try refresh() } }
            .alert("Replace your workspace?", isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } })) {
                Button("Cancel", role: .cancel) { candidate = nil }
                Button("Back up & replace", role: .destructive) { restore() }
            } message: {
                Text("\(candidateName) contains \(candidate?.recordCount ?? 0) records. Current data will be replaced. A complete safety backup will be created before any changes.")
            }
    }
    private func perform(_ action: () throws -> Void) { do { error = nil; try action() } catch { self.error = error.localizedDescription } }
    private func refresh() throws { backups = try BackupService.files(context) }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "StudyPilot-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { let data = try BackupCodec.encode(BackupStore.snapshot(context)); try data.write(to: url, options: .atomic); message = "Exported \(url.lastPathComponent)." }
    }
    private func chooseImport() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { prepare(url) }
    }
    private func prepare(_ url: URL) {
        perform { candidate = try BackupService.read(url); candidateName = url.lastPathComponent }
    }
    private func restore() {
        guard let candidate, focus.state == nil else { return }
        perform {
            let safety = try BackupService.create(context, prefix: "before-restore")
            try BackupStore.restore(candidate, into: context)
            message = "Restored \(candidate.recordCount) records. Previous workspace: \(safety.lastPathComponent)"
            app.selectedAssignmentID = nil; app.selectedNoteID = nil; app.selectedProjectID = nil; app.selectedDeckID = nil
            try refresh(); Task { await ReminderService.shared.reconcile(context: context) }
        }
        self.candidate = nil
    }
}
