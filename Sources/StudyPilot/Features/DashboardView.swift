import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct DashboardView: View {
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @LiveQuery(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \PlannerEvent.startDate) private var events: [PlannerEvent]
    @LiveQuery private var sessions: [StudySession]
    @LiveQuery private var cards: [Flashcard]
    @AppStorage("displayName") private var name = ""
    @State private var editing: Assignment?
    @State private var newEvent = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let calendar = Calendar.current
            let today = assignments.filter { !$0.isDone && ($0.dueDate < now || calendar.isDate($0.dueDate, inSameDayAs: now)) }
            let week = calendar.dateInterval(of: .weekOfYear, for: now)!
            let weekSeconds = sessions.filter { week.contains($0.endedAt) }.reduce(0) { $0 + $1.durationSeconds }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        PageHeading(eyebrow: now.formatted(.dateTime.weekday(.wide).month(.wide).day()), title: name.isEmpty ? "Make today a good day." : "You’ve got this, \(name).", subtitle: "A little clarity. A little focus. A lot of possibility.")
                        Button { app.showingAssignment = true } label: { Label("New assignment", systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                        MetricCard(symbol: "flame", value: "\(StudyAnalytics.streak(sessions: sessions.map(\.record), now: now))", label: "day study streak", color: .orange)
                        MetricCard(symbol: "clock", value: String(format: "%.1f", weekSeconds / 3600), label: "study hours this week", color: .pilot)
                        MetricCard(symbol: "checkmark.circle", value: "\(assignments.filter(\.isDone).count)", label: "assignments completed", color: Color(hex: "2B998C"))
                        MetricCard(symbol: "rectangle.on.rectangle", value: "\(cards.filter { $0.dueDate <= now }.count)", label: "cards ready to review", color: Color(hex: "A178C5"))
                    }
                    nextDeadlineCard(now: now)
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("ONE THING AT A TIME", systemImage: "sparkle").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Color.pilot)
                            Text("Find your focus.").font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("Give your next idea 25 uninterrupted minutes.").foregroundStyle(.secondary)
                            Button { if focus.state == nil { focus.start(minutes: 25, subjectID: nil) }; app.section = .focus } label: { Label("Start a focus session", systemImage: "play.fill") }.buttonStyle(.borderedProminent).padding(.top, 7)
                        }
                        Spacer()
                        DailyStudyGoalView(sessions: sessions.map(\.record), now: now).frame(width: 190)
                    }.padding(26).background(Color.pilot.opacity(0.065), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Text("Your week, at a glance").font(.headline); Spacer(); Button("Open calendar", systemImage: "arrow.up.right") { app.section = .calendar }.buttonStyle(.plain).foregroundStyle(Color.pilot) }
                        HStack(spacing: 8) {
                            ForEach(0..<7, id: \.self) { index in
                                let day = calendar.date(byAdding: .day, value: index, to: week.start)!
                                let isToday = calendar.isDate(day, inSameDayAs: now)
                                let count = assignments.filter { !$0.isDone && calendar.isDate($0.dueDate, inSameDayAs: day) }.count + events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.count
                                VStack(spacing: 10) {
                                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(isToday ? Color.pilot : .secondary)
                                    Text(day.formatted(.dateTime.day())).font(.system(size: 21, weight: isToday ? .bold : .medium, design: .rounded))
                                    Text(count == 0 ? "—" : "\(count) planned").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(.vertical, 15).background(isToday ? Color.pilot.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                    }.pilotCard()
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("Today’s priorities").font(.headline); Spacer(); Text("\(today.count)").font(.caption.bold()).foregroundStyle(.secondary) }
                            if today.isEmpty { EmptyState(symbol: "sun.max", title: "A little breathing room", message: "Nothing due today. Make progress on an upcoming assignment, or take time to recharge.") }
                            ForEach(today.prefix(5)) { assignment in
                                AssignmentRow(assignment: assignment, subject: subjects.first { $0.id == assignment.subjectID }) { editing = assignment }
                            }
                            Button("View all assignments") { app.section = .assignments }.buttonStyle(.plain).foregroundStyle(Color.pilot)
                        }.frame(maxWidth: .infinity, alignment: .topLeading).pilotCard()
                        VStack(alignment: .leading, spacing: 16) {
                            Text("On the horizon").font(.headline)
                            let upcoming = assignments.filter { !$0.isDone && $0.dueDate > (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now) }
                            if upcoming.isEmpty { Text("Upcoming deadlines will appear here.").font(.callout).foregroundStyle(.secondary) }
                            ForEach(upcoming.prefix(3)) { task in
                                Button { editing = task } label: { VStack(alignment: .leading, spacing: 6) { Text(task.title).font(.subheadline.bold()); Text(task.dueDate, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                            }
                            Divider()
                            Text("Examinations").font(.headline)
                            let exams = events.filter { $0.kind == "Exam" && $0.startDate >= now }
                            if exams.isEmpty { Text("No exams scheduled.").font(.callout).foregroundStyle(.secondary) }
                            ForEach(exams.prefix(3)) { exam in
                                VStack(alignment: .leading, spacing: 5) { Text(exam.title).font(.subheadline.bold()); Text(exam.startDate, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                            }
                            Button("Add an exam or study session", systemImage: "plus") { newEvent = true }.buttonStyle(.plain).foregroundStyle(Color.pilot).font(.caption)
                        }.frame(width: 240, alignment: .leading).pilotCard()
                    }
                    HStack(spacing: 12) {
                        Button("Capture a note", systemImage: "square.and.pencil") { app.section = .notes; app.createNote = true }
                        Button("Review flashcards", systemImage: "rectangle.on.rectangle") { app.section = .revision }
                        Button("Plan my study", systemImage: "sparkles") { app.showingStudyPlanner = true }
                        Spacer()
                        Label("Saved on this Mac.", systemImage: "internaldrive").font(.caption).foregroundStyle(.tertiary)
                    }.buttonStyle(.bordered)
                }.padding(30)
            }
        }.sheet(item: $editing) { AssignmentEditor(assignment: $0) }
            .sheet(isPresented: $newEvent) { EventEditor() }
    }

    @ViewBuilder private func nextDeadlineCard(now: Date) -> some View {
        if let next = assignments.filter({ !$0.isDone }).min(by: {
            $0.dueDate == $1.dueDate ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.dueDate < $1.dueDate
        }) {
            let overdue = next.dueDate < now
            Button { editing = next } label: {
                HStack(spacing: 16) {
                    Image(systemName: overdue ? "exclamationmark.circle.fill" : "calendar.badge.clock")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(overdue ? Color.red : Color.pilot)
                        .frame(width: 48, height: 48)
                        .background((overdue ? Color.red : Color.pilot).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(overdue ? "OVERDUE" : "NEXT DEADLINE")
                            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4)
                            .foregroundStyle(overdue ? Color.red : Color.pilot)
                        Text(next.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                        Text(next.dueDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(next.dueDate, style: .relative).font(.subheadline.weight(.semibold)).foregroundStyle(overdue ? Color.red : Color.primary)
                        Text(overdue ? "past due" : "remaining").font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this assignment for editing")
            .pilotCard()
        } else {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 25)).foregroundStyle(Color(hex: "2B998C"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("You’re all caught up").font(.headline)
                    Text("Add an assignment whenever new work comes in.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add assignment", systemImage: "plus") { app.showingAssignment = true }.buttonStyle(.bordered)
            }.pilotCard()
        }
    }
}
struct MetricCard: View {
    let symbol: String
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
}
