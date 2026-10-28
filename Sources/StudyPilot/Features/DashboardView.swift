import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery private var sessions: [StudySession]
    @LiveQuery(sort: \PlannerEvent.startDate) private var plannerEvents: [PlannerEvent]
    @LiveQuery private var cards: [Flashcard]
    @LiveQuery(sort: \Notebook.title) private var notebooks: [Notebook]
    @LiveQuery(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @AppStorage("dailyStudyGoalMinutes") private var goalMinutes = 60
    @AppStorage("hasCreatedStudyPlan") private var hasCreatedStudyPlan = false
    private var hasPlan: Bool { hasCreatedStudyPlan || !plannerEvents.isEmpty }
    private var dueToday: Int { assignments.filter { !$0.isDone && Calendar.current.isDate($0.dueDate, inSameDayAs: app.now) }.count }
    private var overdue: Int { assignments.filter { !$0.isDone && $0.dueDate < app.now }.count }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    if assignments.isEmpty || !hasPlan || sessions.isEmpty { gettingStarted }
                    summary
                    notebookShelf
                    if geometry.size.width >= 920 {
                        HStack(alignment: .top, spacing: 28) {
                            TodayAgendaView().frame(maxWidth: .infinity, alignment: .topLeading).pilotCard()
                            utilities.frame(width: 310).pilotCard()
                        }
                    } else {
                        TodayAgendaView().pilotCard()
                        utilities.pilotCard()
                    }
                }.padding(30).frame(maxWidth: 1280, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
    private var hero: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.now, format: .dateTime.weekday(.wide).month(.wide).day()).font(.system(size: 11, weight: .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Color.pilot)
                Text("Today").font(.system(size: 36, weight: .semibold, design: .rounded))
                Text(daySummary).font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 10) {
                Button("Plan my study", systemImage: "calendar.badge.clock") { app.showingStudyPlanner = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button(focus.state == nil ? "Start a focus session" : "Return to focus", systemImage: "timer") {
                    if focus.state == nil { focus.start(minutes: 25, subjectID: assignments.first(where: { !$0.isDone })?.subjectID) }
                    app.section = .focus
                }.buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(Color.pilot)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 24)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Color.pilot.opacity(0.16), Color.pilotBlue.opacity(0.09), Color(nsColor: .controlBackgroundColor).opacity(0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.pilotBlue.opacity(0.07)).frame(width: 230, height: 230).offset(x: 70, y: -80)
                Circle().fill(Color.pilot.opacity(0.06)).frame(width: 150, height: 150).offset(x: -100, y: 90)
            }.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.pilot.opacity(0.12), lineWidth: 0.7))
        .shadow(color: Color.pilot.opacity(0.08), radius: 24, y: 10)
    }
    private var daySummary: String {
        if overdue > 0 { return "\(overdue) overdue assignment\(overdue == 1 ? "" : "s") need your attention." }
        if dueToday > 0 { return "\(dueToday) assignment\(dueToday == 1 ? " is" : "s are") due today. Your plan is ready when you are." }
        if let next = assignments.first(where: { !$0.isDone && $0.dueDate > app.now }) { return "Next up: \(next.title), due \(next.dueDate.formatted(date: .abbreviated, time: .shortened))." }
        return "Your workspace is clear. Use the time to get ahead or review."
    }
    private var gettingStarted: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR FIRST STUDY LOOP").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Color.pilot)
                Text(nextJourneyTitle).font(.title3.bold())
                Text(nextJourneyDetail).font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                journeyPill("1", "Deadline", complete: !assignments.isEmpty)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                journeyPill("2", "Plan", complete: hasPlan)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                journeyPill("3", "Focus", complete: !sessions.isEmpty)
            }
            Button(nextJourneyAction, systemImage: nextJourneySymbol) { runNextJourneyAction() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(20)
        .background(LinearGradient(colors: [Color.pilot.opacity(0.13), Color.notebookInk.opacity(0.06)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.pilot.opacity(0.16), lineWidth: 0.5))
    }
    private var nextJourneyTitle: String {
        if assignments.isEmpty { return "Add one real deadline" }
        if !hasPlan { return "Turn it into a study plan" }
        return "Start your first focus session"
    }
    private var nextJourneyDetail: String {
        if assignments.isEmpty { return "A title, due date, and honest time estimate are enough." }
        if !hasPlan { return "StudyPilot will work around your selected calendar commitments." }
        return "Use the plan while it is fresh and record the time you spend."
    }
    private var nextJourneyAction: String { assignments.isEmpty ? "Open setup" : !hasPlan ? "Build plan" : "Start focus" }
    private var nextJourneySymbol: String { assignments.isEmpty ? "wand.and.stars" : !hasPlan ? "calendar.badge.clock" : "timer" }
    private func runNextJourneyAction() {
        if assignments.isEmpty { app.showingFirstRunSetup = true }
        else if !hasPlan { app.showingStudyPlanner = true }
        else { if focus.state == nil { focus.start(minutes: 25, subjectID: assignments.first(where: { !$0.isDone })?.subjectID) }; app.section = .focus }
    }
    private func journeyPill(_ number: String, _ label: String, complete: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle").foregroundStyle(complete ? Color.pilot : Color.secondary)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(complete ? .primary : .secondary)
        }.padding(.horizontal, 9).padding(.vertical, 7).background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: Capsule())
    }
    private var summary: some View {
        HStack(spacing: 14) {
            summaryButton(value: dueToday, label: "Due today", filter: .today, symbol: "calendar", tint: .pilot)
            summaryButton(value: overdue, label: "Overdue", filter: .overdue, symbol: "clock.badge.exclamationmark", tint: overdue > 0 ? .orange : .pilotBlue)
            let minutes = DailyStudyProgress(sessions: sessions.map(\.record), goalMinutes: goalMinutes, now: app.now).minutes
            Button { app.section = .focus } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label("Study time", systemImage: "timer").font(.caption.weight(.semibold)).foregroundStyle(Color.pilot); Spacer(); Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary) }
                    HStack(alignment: .firstTextBaseline, spacing: 5) { Text("\(minutes)").font(.system(size: 30, weight: .medium)).monospacedDigit(); Text("/ \(goalMinutes) min").font(.caption).foregroundStyle(.secondary) }
                    ProgressView(value: min(1, Double(minutes) / Double(max(1, goalMinutes)))).tint(Color.pilot)
                }.frame(maxWidth: .infinity, alignment: .leading).pilotCard().contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
    private func summaryButton(value: Int, label: String, filter: AssignmentTimeFilter, symbol: String, tint: Color) -> some View {
        Button { app.assignmentTimeFilter = filter; app.section = .assignments } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label(label, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint); Spacer(); Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary) }
                Text("\(value)").font(.system(size: 30, weight: .medium)).monospacedDigit().foregroundStyle(tint)
                Text(value == 0 ? "Nothing waiting" : "Open assignments").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).pilotCard().contentShape(Rectangle())
        }.buttonStyle(.plain).help("View assignments \(label)")
    }
    private var notebookShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Study materials").font(.system(size: 14, weight: .semibold)); Spacer(); Button("All notebooks") { app.selectedNotebookID = nil; app.section = .notebooks }.buttonStyle(.link).font(.caption) }
            if notebooks.isEmpty {
                Button { app.selectedNotebookID = nil; app.section = .notebooks } label: {
                    HStack(spacing: 14) { Image(systemName: "books.vertical").font(.title2).foregroundStyle(Color.notebookInk); VStack(alignment: .leading, spacing: 4) { Text("Bring your reading together").font(.callout.weight(.medium)); Text("Create a notebook for sources, class notes, and revision.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.right").foregroundStyle(.secondary) }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.notebookInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                HStack(spacing: 12) {
                    ForEach(notebooks.prefix(3)) { notebook in
                        Button { app.selectedNotebookID = notebook.id; app.section = .notebooks } label: {
                            HStack(spacing: 12) { Image(systemName: "book.closed.fill").font(.title3).foregroundStyle(Color.pilot).frame(width: 36, height: 36).background(Color.pilot.opacity(0.09), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 5) { Text(notebook.title).font(.callout.weight(.semibold)).lineLimit(1); Text("\(notes.filter { $0.notebookID == notebook.id }.count) items").font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.pilot.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.pilot.opacity(0.08), lineWidth: 0.5)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.pilotCard()
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
                            Capsule().fill(LinearGradient(colors: [Color.pilot.opacity(day.minutes == 0 ? 0.12 : 0.9), Color.pilotBlue.opacity(day.minutes == 0 ? 0.08 : 0.62)], startPoint: .bottom, endPoint: .top)).frame(width: 15, height: max(3, 48 * Double(day.minutes) / Double(max(1, days.map(\.minutes).max() ?? 1))))
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
