import SwiftUI
import SwiftData
import StudyPilotData

@main struct StudyPilotApp: App {
    @State private var app = AppState()
    @State private var focus = FocusController()
    private let container: ModelContainer?
    private let startupError: String?
    init() {
        do {
            let folder: URL
            if let index = CommandLine.arguments.firstIndex(of: "--data-directory"), CommandLine.arguments.count > index + 1 {
                folder = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            } else if let file = Bundle.main.url(forResource: "QADataDirectory", withExtension: "txt"), let path = try? String(contentsOf: file, encoding: .utf8) {
                folder = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
            } else {
                folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("StudyPilot", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = try DataStore.makeContainer(at: folder.appendingPathComponent("StudyPilot.store"))
            try DataStore.seedSubjectsIfNeeded(store.mainContext)
            container = store; startupError = nil
        } catch { container = nil; startupError = error.localizedDescription }
    }
    var body: some Scene {
        Window("StudyPilot", id: "main") {
            if let container {
                RootView().environment(app).environment(focus).modelContainer(container).tint(.pilot)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text("Your workspace couldn’t open").font(.title2.bold())
                    Text(startupError ?? "Unknown storage error").textSelection(.enabled)
                    Text("Your database has not been replaced. Check disk space and folder permissions, then relaunch StudyPilot.").foregroundStyle(.secondary)
                }.padding(40).frame(width: 600)
            }
        }.defaultSize(width: 1280, height: 850)
            .commands {
                CommandGroup(after: .appInfo) { AppUpdateButton().environment(focus) }
                CommandGroup(replacing: .newItem) {
                    Button("New Assignment") { app.showingAssignment = true }.keyboardShortcut("n")
                    Button("New Note") { app.section = .notes; app.createNote = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                }
                CommandMenu("Workspace") {
                    Button("Search & Quick Actions") { app.showingSearch = true }.keyboardShortcut("k")
                    Button("Plan My Study") { app.showingStudyPlanner = true }.keyboardShortcut("p", modifiers: [.command, .shift])
                    Button("Focus Session") { app.section = .focus; if focus.state == nil { focus.start(minutes: 25, subjectID: nil) } }.keyboardShortcut("f", modifiers: [.command, .shift])
                    Divider()
                    ForEach(Array(AppSection.allCases.enumerated()), id: \.element.id) { index, section in
                        Button(section.rawValue) { app.section = section }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    }
                }
                CommandGroup(replacing: .appSettings) { Button("Settings…") { app.showingSettings = true }.keyboardShortcut(",") }
            }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FocusController.self) private var focus
    private let ticks = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(AppState.self) private var app
    @State private var visibility: NavigationSplitViewVisibility = .all
    @AppStorage("appearance") private var appearance = "System"
    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $visibility) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill").font(.title3).foregroundStyle(.white).frame(width: 38, height: 38).background(Color.pilot.gradient, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("StudyPilot").font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("YOUR STUDENT WORKSPACE").font(.system(size: 7, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 20)
                List(selection: $app.section) {
                    Section("WORKSPACE") {
                        ForEach(AppSection.allCases.prefix(3)) { section in Label(section.rawValue, systemImage: section.symbol).tag(section).padding(.vertical, 5) }
                    }
                    Section("LEARN & GROW") {
                        ForEach(AppSection.allCases.dropFirst(3).prefix(4)) { section in Label(section.rawValue, systemImage: section.symbol).tag(section).padding(.vertical, 5) }
                    }
                    Section { Label(AppSection.library.rawValue, systemImage: AppSection.library.symbol).tag(AppSection.library).padding(.vertical, 5) }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 10) {
                    Label("A little progress, every day.", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
                    Button { app.showingSettings = true } label: { Label("Settings & backups", systemImage: "gearshape") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 270)
        } detail: {
            Group {
                switch app.section {
                case .assignments: AssignmentsView()
                case .dashboard: DashboardView()
                case .calendar: PlannerCalendarView()
                case .library: LibraryView()
                case .notes: NotesView()
                case .revision: RevisionView()
                case .focus: FocusView()
                case .progress: AcademicProgressView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
                .toolbar {
                    ToolbarItem(placement: .navigation) { Text(app.section.rawValue).font(.headline).foregroundStyle(.secondary) }
                    ToolbarItemGroup(placement: .primaryAction) {
                        AppearanceControl()
                        Button { app.showingSearch = true } label: { Image(systemName: "magnifyingglass") }.help("Search workspace (⌘K)")
                        Button { app.showingAssignment = true } label: { Label("New assignment", systemImage: "plus") }.help("New assignment (⌘N)")
                    }
                }
        }.frame(minWidth: 960, minHeight: 700)
            .sheet(isPresented: $app.showingAssignment) { AssignmentEditor() }
            .sheet(isPresented: $app.showingSearch) { CommandPalette() }
            .sheet(isPresented: $app.showingSettings) { SettingsView() }
            .sheet(isPresented: $app.showingStudyPlanner) { StudyPlanningView() }
            .alert("Something needs attention", isPresented: Binding(get: { app.error != nil }, set: { if !$0 { app.error = nil } })) { Button("OK") { app.error = nil } } message: { Text(app.error ?? "") }
            .onReceive(NotificationCenter.default.publisher(for: .studyPilotQueryFailed)) { notice in app.error = notice.userInfo?["message"] as? String }
            .onReceive(ticks) { _ in
                focus.tick(context: context)
                if abs(app.now.timeIntervalSinceNow) >= 30 { app.now = Date() }
            }
            .task {
                focus.tick(context: context)
                await ReminderService.shared.reconcile(context: context)
                do { try BackupService.automatic(context) } catch { app.error = "Automatic backup could not be created: \(error.localizedDescription)" }
            }
            .onChange(of: scenePhase) { if scenePhase == .active { focus.tick(context: context); Task { await ReminderService.shared.reconcile(context: context) } } }
            .onChange(of: focus.error) { if let error = focus.error { app.error = error; focus.error = nil } }
            .preferredColorScheme(appearance == "Light" ? .light : appearance == "Dark" ? .dark : nil)
    }
}
