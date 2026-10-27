import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery private var sessions: [StudySession]
    @LiveQuery private var cards: [Flashcard]
    @AppStorage("dailyStudyGoalMinutes") private var goalMinutes = 60
    private var dueToday: Int { assignments.filter { !$0.isDone && Calendar.current.isDate($0.dueDate, inSameDayAs: app.now) }.count }
    private var overdue: Int { assignments.filter { !$0.isDone && $0.dueDate < app.now }.count }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").font(.system(size: 28, weight: .semibold))
                        Text(app.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Plan my study") { app.showingStudyPlanner = true }.buttonStyle(.bordered)
                    }
                    summary
                    if geometry.size.width >= 920 {
                        HStack(alignment: .top, spacing: 28) {
                            TodayAgendaView().frame(maxWidth: .infinity, alignment: .topLeading)
                            Divider()
                            utilities.frame(width: 280)
                        }
                    } else {
                        TodayAgendaView()
                        Divider()
                        utilities
                    }
                }.padding(28).frame(maxWidth: 1220, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
    private var summary: some View {
        HStack(spacing: 24) {
            summaryButton(value: dueToday, label: "due today", filter: .today)
            Divider().frame(height: 24)
            summaryButton(value: overdue, label: "overdue", filter: .overdue)
            Divider().frame(height: 24)
            let minutes = DailyStudyProgress(sessions: sessions.map(\.record), goalMinutes: goalMinutes, now: app.now).minutes
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(minutes)").font(.system(size: 22, weight: .medium)).monospacedDigit(); Text("minutes studied").font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.padding(.vertical, 14).overlay(alignment: .top) { Divider() }.overlay(alignment: .bottom) { Divider() }
    }
    private func summaryButton(value: Int, label: String, filter: AssignmentTimeFilter) -> some View {
        Button { app.assignmentTimeFilter = filter; app.section = .assignments } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(value)").font(.system(size: 22, weight: .medium)).monospacedDigit().foregroundStyle(filter == .overdue && value > 0 ? Color.orange : .primary)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain).help("View assignments \(label)")
    }
    private var utilities: some View {
        VStack(alignment: .leading, spacing: 24) {
            QuickTaskEntry(compact: true)
            Divider()
            WorkloadWeekView(assignments: assignments.map(\.record), now: app.now)
            Divider()
            studyProgress
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Shortcuts").font(.system(size: 13, weight: .semibold))
                Button(focus.state == nil ? "Start 25-minute focus" : "Open focus session", systemImage: "timer") { if focus.state == nil { focus.start(minutes: 25, subjectID: nil) }; app.section = .focus }
                Button("New note", systemImage: "square.and.pencil") { app.section = .notes; app.createNote = true }
                Button("Review flashcards (\(cards.filter { $0.dueDate <= app.now }.count) due)", systemImage: "rectangle.on.rectangle") { app.section = .revision }
                Button("Open assistant", systemImage: "bubble.left") { app.ask("What tasks are due today?") }
            }.buttonStyle(.link).font(.callout)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var studyProgress: some View {
        let value = DailyStudyProgress(sessions: sessions.map(\.record), goalMinutes: goalMinutes, now: app.now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Study time").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(value.minutes) / \(value.goalMinutes) min").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            ProgressView(value: value.fraction)
            Text("\(StudyAnalytics.streak(sessions: sessions.map(\.record), now: app.now))-day streak · \(assignments.filter(\.isDone).count) assignments completed").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct WorkloadWeekView: View {
    @Environment(AppState.self) private var app
    let assignments: [AssignmentRecord]
    let now: Date
    private var days: [StudyWorkloadDay] { TodayWorkspace.workload(assignments: assignments, now: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Next 7 days").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(days.reduce(0) { $0 + $1.minutes }) min").font(.caption).foregroundStyle(.secondary) }
            Text("Estimated effort by deadline").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    Button { app.openCalendar(day.date) } label: {
                        VStack(spacing: 5) {
                            Text(day.minutes == 0 ? "—" : "\(day.minutes)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            Rectangle().fill(Color.pilot.opacity(day.minutes == 0 ? 0.12 : 0.75)).frame(width: 15, height: max(3, 48 * Double(day.minutes) / Double(max(1, days.map(\.minutes).max() ?? 1))))
                            Text(day.date, format: .dateTime.weekday(.abbreviated)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(day.date, format: .dateTime.day()).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.count) assignments, \(day.minutes) estimated minutes")
                }
            }.frame(height: 106, alignment: .bottom)
            Text("Select a day to open Calendar. These estimates aren't booked sessions.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
