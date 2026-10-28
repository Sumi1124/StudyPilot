import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

public enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Today", assignments = "Assignments", calendar = "Calendar", notes = "Notes", revision = "Revision", focus = "Focus", progress = "Progress", library = "Subjects & projects", chat = "AI Chat", notebooks = "Notebooks"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .assignments: "checklist"
        case .calendar: "calendar"
        case .notes: "note.text"
        case .revision: "rectangle.on.rectangle"
        case .focus: "timer"
        case .progress: "chart.xyaxis.line"
        case .library: "books.vertical"
        case .chat: "bubble.left.and.bubble.right"
        case .notebooks: "books.vertical"
        }
    }
}

@MainActor @Observable final class AppState {
    var section: AppSection = .dashboard
    var now = Date()
    var showingAssignment = false
    var showingSearch = false
    var showingSettings = false
    var checkForUpdatesAfterSettings = false
    var showingStudyPlanner = false
    var showingFirstRunSetup = false
    var selectedNoteID: UUID?
    var selectedNotebookID: UUID?
    var selectedAssignmentID: UUID?
    var selectedDeckID: UUID?
    var selectedSubjectID: UUID?
    var selectedProjectID: UUID?
    var createNote = false
    var selectedCalendarDate: Date?
    var assignmentTimeFilter: AssignmentTimeFilter = .any
    var chatDraft: String?
    var completionUndo: CompletionUndo?
    var planning: CalendarPlanningService?
    func ask(_ prompt: String) { chatDraft = prompt; section = .chat }
    func openCalendar(_ date: Date) { selectedCalendarDate = date; section = .calendar }
    func toggleCompletion(_ assignment: Assignment, context: ModelContext) {
        let before = assignment.record
        var after = before
        after.status = assignment.isDone ? TaskStatus.todo.rawValue : TaskStatus.done.rawValue
        after.completedAt = after.status == TaskStatus.done.rawValue ? Date() : nil
        assignment.apply(after)
        if save(context, completionChanges: [after]) {
            completionUndo = CompletionUndo(before: before, after: after, taskID: "local:\(after.id.uuidString)", title: after.title, completed: after.status == TaskStatus.done.rawValue, expires: planning?.settings.completedTasks?["local:\(after.id.uuidString)"]?.removeAfter ?? Date().addingTimeInterval(90))
        } else { assignment.apply(before) }
    }
    func finishTask(id: String, title: String, context: ModelContext) {
        do {
            if let localID = StudyTaskLink.localID(id) {
                guard let assignment = try context.fetch(FetchDescriptor<Assignment>()).first(where: { $0.id == localID }) else {
                    throw PlanningError.invalid("The linked assignment could not be found. Your sessions were kept.")
                }
                if !assignment.isDone { toggleCompletion(assignment, context: context) }
            } else {
                guard id.hasPrefix("calendar:"), let planning else { throw PlanningError.invalid("This task cannot be completed yet.") }
                try planning.recordTaskCompletion(id: id, title: title, completed: true)
                ReminderService.shared.finishedTaskIDs = Set(planning.settings.completedTasks?.keys.map { $0 } ?? [])
                Task { await ReminderService.shared.reconcile(context: context) }
                completionUndo = CompletionUndo(before: nil, after: nil, taskID: id, title: title, completed: true, expires: planning.settings.completedTasks?[id]?.removeAfter ?? Date().addingTimeInterval(90))
            }
        } catch { self.error = error.localizedDescription }
    }
    func undoCompletion(context: ModelContext) {
        guard let change = completionUndo, change.expires > Date() else { completionUndo = nil; return }
        do {
            if let before = change.before, let after = change.after {
                guard let task = try context.fetch(FetchDescriptor<Assignment>()).first(where: { $0.id == after.id }), task.record == after else {
                    completionUndo = nil; error = "This assignment changed after completion. Your newer edit has been kept."; return
                }
                task.apply(before)
                guard save(context, completionChanges: [before]) else { task.apply(after); return }
            } else {
                guard let planning else { throw PlanningError.invalid("Calendars are still opening.") }
                try planning.recordTaskCompletion(id: change.taskID, title: change.title, completed: false)
                ReminderService.shared.finishedTaskIDs = Set(planning.settings.completedTasks?.keys.map { $0 } ?? [])
                Task { await ReminderService.shared.reconcile(context: context) }
            }
            completionUndo = nil
        } catch { self.error = "Undo could not be saved: \(error.localizedDescription)" }
    }
    var error: String?
    @discardableResult func save(_ context: ModelContext, updateReminders: Bool = true, completionChanges: [AssignmentRecord] = []) -> Bool {
        do { try context.save() }
        catch { self.error = "Your changes could not be saved: \(error.localizedDescription)"; return false }
        if let planning {
            for task in completionChanges {
                do { try planning.recordTaskCompletion(id: "local:\(task.id.uuidString)", title: task.title, completed: task.status == TaskStatus.done.rawValue) }
                catch { self.error = "The assignment was saved, but linked-session cleanup could not be saved: \(error.localizedDescription)" }
            }
        }
        if let planning { ReminderService.shared.finishedTaskIDs = Set(planning.settings.completedTasks?.keys.map { $0 } ?? []) }
        if updateReminders { Task { await ReminderService.shared.reconcile(context: context) } }
        return true
    }
}

struct CompletionUndo {
    let before: AssignmentRecord?
    let after: AssignmentRecord?
    let taskID: String
    let title: String
    let completed: Bool
    let expires: Date
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x6877E8
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static var pilot: Color { Color(nsColor: .controlAccentColor) }
}
extension Subject { var color: Color { Color(hex: colorHex) } }
extension Assignment {
    var isDone: Bool { status == TaskStatus.done.rawValue }
    var progress: Double { PlannerLogic.progress(record) }
}
extension View {
    func pilotCard() -> some View {
        self.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(nsColor: .separatorColor).opacity(0.24), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }
}
struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !eyebrow.isEmpty { Text(eyebrow.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.pilot) }
            Text(title).font(.system(size: 28, weight: .semibold))
            if !subtitle.isEmpty { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27, weight: .medium)).foregroundStyle(Color.pilot).frame(width: 58, height: 58).background(Color.pilot.opacity(0.10), in: Circle())
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }.frame(maxWidth: .infinity).padding(40)
    }
}
struct SubjectBadge: View {
    let subject: Subject?
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(subject?.color ?? .secondary).frame(width: 6, height: 6)
            Text(subject?.name ?? "Independent study").font(.caption)
        }.foregroundStyle(.secondary)
    }
}
struct SubjectPicker: View {
    let subjects: [Subject]
    @Binding var selection: UUID?
    var emptyLabel = "Independent study"
    var body: some View {
        Picker("Subject", selection: $selection) {
            Text(emptyLabel).tag(nil as UUID?)
            ForEach(subjects) { Text($0.name).tag(Optional($0.id)) }
        }
    }
}
struct SheetActions: View {
    let title: String
    var disabled = false
    let cancel: () -> Void
    let save: () -> Void
    var body: some View {
        HStack { Spacer(); Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button(title, action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(disabled)
        }.padding(20)
    }
}
