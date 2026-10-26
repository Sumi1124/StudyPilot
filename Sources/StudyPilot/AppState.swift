import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

public enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Overview", assignments = "Assignments", calendar = "Calendar", notes = "Notes", revision = "Revision", focus = "Focus", progress = "Progress", library = "Subjects & projects", chat = "AI Chat"
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
    var selectedNoteID: UUID?
    var selectedAssignmentID: UUID?
    var selectedDeckID: UUID?
    var selectedSubjectID: UUID?
    var selectedProjectID: UUID?
    var createNote = false
    var selectedCalendarDate: Date?
    var assignmentTimeFilter: AssignmentTimeFilter = .any
    var chatDraft: String?
    var completionUndo: CompletionUndo?
    func ask(_ prompt: String) { chatDraft = prompt; section = .chat }
    func openCalendar(_ date: Date) { selectedCalendarDate = date; section = .calendar }
    func toggleCompletion(_ assignment: Assignment, context: ModelContext) {
        let before = assignment.record
        var after = before
        after.status = assignment.isDone ? TaskStatus.todo.rawValue : TaskStatus.done.rawValue
        after.completedAt = after.status == TaskStatus.done.rawValue ? Date() : nil
        assignment.apply(after)
        do {
            try context.save()
            completionUndo = CompletionUndo(before: before, after: after, expires: Date().addingTimeInterval(90))
            Task { await ReminderService.shared.reconcile(context: context) }
        } catch { assignment.apply(before); self.error = "Completion could not be saved: \(error.localizedDescription)" }
    }
    func undoCompletion(context: ModelContext) {
        guard let change = completionUndo else { return }
        do {
            guard let task = try context.fetch(FetchDescriptor<Assignment>()).first(where: { $0.id == change.after.id }), task.record == change.after else {
                completionUndo = nil; error = "This assignment changed after completion. Your newer edit has been kept."; return
            }
            task.apply(change.before)
            do { try context.save() } catch { task.apply(change.after); throw error }
            completionUndo = nil
            Task { await ReminderService.shared.reconcile(context: context) }
        } catch { self.error = "Undo could not be saved: \(error.localizedDescription)" }
    }
    var error: String?
    @discardableResult func save(_ context: ModelContext, updateReminders: Bool = true) -> Bool {
        do { try context.save(); if updateReminders { Task { await ReminderService.shared.reconcile(context: context) } }; return true }
        catch { self.error = "Your changes could not be saved: \(error.localizedDescription)"; return false }
    }
}

struct CompletionUndo {
    let before: AssignmentRecord
    let after: AssignmentRecord
    let expires: Date
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x6877E8
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static let pilot = Color(hex: "6877E8")
}
extension Subject { var color: Color { Color(hex: colorHex) } }
extension Assignment {
    var isDone: Bool { status == TaskStatus.done.rawValue }
    var progress: Double { PlannerLogic.progress(record) }
}
extension View {
    func pilotCard() -> some View {
        self.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.055), lineWidth: 1))
    }
}
struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(Color.pilot)
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
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
            Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(Color.pilot)
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
