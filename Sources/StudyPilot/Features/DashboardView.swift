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
    @AppStorage("displayName") private var name = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeading(eyebrow: app.now.formatted(.dateTime.weekday(.wide).month(.wide).day()), title: name.isEmpty ? "Your study day." : "Your study day, \(name).", subtitle: "See what needs attention, capture a task, and take the next step.")
                    Button("Ask my assistant", systemImage: "bubble.left.and.bubble.right") { app.ask("What tasks are due today?") }.buttonStyle(.bordered)
                }
                QuickTaskEntry().pilotCard()
                TodayAgendaView()
                WorkloadWeekView(assignments: assignments.map(\.record), now: app.now)
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Make a little progress", systemImage: "timer").font(.title3.bold())
                        Text("Choose one thing and give it your attention.").foregroundStyle(.secondary)
                        HStack {
                            Button(focus.state == nil ? "Focus for 25 minutes" : "Open focus session", systemImage: "play.fill") {
                                if focus.state == nil { focus.start(minutes: 25, subjectID: nil) }; app.section = .focus
                            }.buttonStyle(.borderedProminent)
                            Button("Capture a note", systemImage: "square.and.pencil") { app.section = .notes; app.createNote = true }
                        }
                        Button("Review \(cards.filter { $0.dueDate <= app.now }.count) due flashcards", systemImage: "rectangle.on.rectangle") { app.section = .revision }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    DailyStudyGoalView(sessions: sessions.map(\.record), now: app.now).frame(width: 180)
                }.padding(24).background(Color.pilot.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
                HStack(spacing: 14) {
                    MetricCard(symbol: "flame", value: "\(StudyAnalytics.streak(sessions: sessions.map(\.record), now: app.now))", label: "day study streak", color: .orange)
                    MetricCard(symbol: "checklist", value: "\(assignments.filter { !$0.isDone }.count)", label: "unfinished assignments", color: .pilot)
                    MetricCard(symbol: "checkmark.circle", value: "\(assignments.filter(\.isDone).count)", label: "assignments completed", color: Color(hex: "2B998C"))
                }
            }.padding(28)
        }
    }
}
struct WorkloadWeekView: View {
    @Environment(AppState.self) private var app
    let assignments: [AssignmentRecord]
    let now: Date
    private var days: [StudyWorkloadDay] { TodayWorkspace.workload(assignments: assignments, now: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Deadline workload", systemImage: "chart.bar.fill").font(.headline); Spacer(); Text("\(days.reduce(0) { $0 + $1.minutes }) min in the next 7 days").font(.caption).foregroundStyle(.secondary) }
            Text("Estimated effort for unfinished assignments due each day. This is not reserved calendar time. Select a day to open its calendar.").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { day in
                    Button { app.openCalendar(day.date) } label: {
                        VStack(spacing: 8) {
                            Text(day.minutes == 0 ? "—" : "\(day.minutes)m").font(.caption.bold()).foregroundStyle(.primary)
                            RoundedRectangle(cornerRadius: 6).fill(Color.pilot.opacity(day.minutes == 0 ? 0.12 : 0.75)).frame(height: max(5, 65 * Double(day.minutes) / Double(max(1, days.map(\.minutes).max() ?? 1))))
                            Text(day.date, format: .dateTime.weekday(.abbreviated).day()).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.count) assignments, \(day.minutes) estimated minutes")
                }
            }.frame(height: 112, alignment: .bottom)
        }.pilotCard()
    }
}
struct MetricCard: View {
    let symbol: String
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
}
