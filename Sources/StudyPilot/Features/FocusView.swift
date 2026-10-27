import SwiftUI
import SwiftData
import Charts
import StudyPilotCore
import StudyPilotData

struct FocusView: View {
    @Environment(\.modelContext) private var context
    @Environment(FocusController.self) private var focus
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @LiveQuery(sort: \StudySession.endedAt, order: .reverse) private var sessions: [StudySession]
    @State private var subjectID: UUID?
    @State private var duration = 25
    @State private var ending = false
    private var shownSeconds: Int { Int(ceil(focus.state == nil ? Double(duration * 60) : focus.remaining)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(eyebrow: "Be here, now", title: "Focus", subtitle: "Set a timer and record your study time.")
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 24) {
                        Text(focus.state?.isBreak == true ? "Break" : "Focus session").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 3)
                            Circle().trim(from: 0, to: focus.state.map { min(1, max(0, focus.remaining / $0.plannedSeconds)) } ?? 1)
                                .stroke(focus.state == nil ? Color.secondary.opacity(0.22) : Color.pilot, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 10) {
                                Text(String(format: "%02d:%02d", shownSeconds / 60, shownSeconds % 60)).font(.system(size: 60, weight: .light)).monospacedDigit().contentTransition(.numericText())
                                Text(focus.state == nil ? "Ready" : focus.isRunning ? "Running" : "Paused").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(width: 240, height: 240).accessibilityElement(children: .combine)
                        if let state = focus.state {
                            Text(state.isBreak ? "Break" : subjects.first { $0.id == state.subjectID }?.name ?? "Independent study").font(.headline)
                            HStack {
                                Button(focus.isRunning ? "Pause" : "Resume", systemImage: focus.isRunning ? "pause.fill" : "play.fill") { if focus.isRunning { focus.pause() } else { focus.resume() } }.buttonStyle(.borderedProminent).controlSize(.large)
                                Button("End & save") { ending = true }.controlSize(.large)
                            }
                        } else {
                            SubjectPicker(subjects: subjects, selection: $subjectID).frame(maxWidth: 300)
                            HStack {
                                Button("25 min") { duration = 25 }; Button("50 min") { duration = 50 }
                                Stepper("\(duration) min", value: $duration, in: 1...240).frame(width: 120)
                            }
                            HStack {
                                Button("Start focus", systemImage: "play.fill") { focus.start(minutes: duration, subjectID: subjectID) }.buttonStyle(.borderedProminent).controlSize(.large)
                                Button("5-min break") { focus.start(minutes: 5, subjectID: nil, isBreak: true) }.controlSize(.large)
                            }
                        }
                        if let message = focus.completionMessage { Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        Text("Your timer keeps time in the background and recovers after relaunch. Breaks are not counted as study time.").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 330)
                    }.padding(18).frame(maxWidth: .infinity).pilotCard()
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Study time").font(.title3.bold())
                        DailyStudyGoalView(sessions: sessions.map(\.record), now: app.now, editable: true)
                        Divider()
                        Text("Past 7 days").font(.headline)
                        StudyTimeChart(sessions: sessions.map(\.record)).frame(height: 180)
                        Divider()
                        Text("By subject · this week").font(.headline)
                        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!
                        let weekly = sessions.filter { week.contains($0.endedAt) }
                        ForEach(subjects) { subject in
                            let seconds = weekly.filter { $0.subjectID == subject.id }.reduce(0) { $0 + $1.durationSeconds }
                            if seconds > 0 { HStack { SubjectBadge(subject: subject); Spacer(); Text("\(Int(seconds / 60)) min").font(.caption) } }
                        }
                        let independent = weekly.filter { $0.subjectID == nil }.reduce(0) { $0 + $1.durationSeconds }
                        if independent > 0 { HStack { Text("Independent study"); Spacer(); Text("\(Int(independent / 60)) min") }.font(.caption).foregroundStyle(.secondary) }
                        if weekly.isEmpty { Text("Your study time will appear here after your first session.").foregroundStyle(.secondary).font(.callout) }
                    }.frame(width: 235).pilotCard()
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Session history").font(.title3.bold())
                    if sessions.isEmpty { Text("No sessions recorded yet.").foregroundStyle(.secondary).padding(.vertical, 20) }
                    ForEach(sessions.prefix(100)) { session in
                        HStack {
                            Image(systemName: session.completed ? "checkmark.circle.fill" : "clock").foregroundStyle(session.completed ? Color.pilot : .secondary)
                            SubjectBadge(subject: subjects.first { $0.id == session.subjectID })
                            Spacer()
                            Text(session.endedAt, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary)
                            Text("\(Int(session.durationSeconds / 60))m \(Int(session.durationSeconds) % 60)s").monospacedDigit().frame(width: 75, alignment: .trailing)
                        }.font(.caption).padding(.vertical, 5)
                    }
                }.pilotCard()
            }.padding(30)
        }.alert("End this session?", isPresented: $ending) {
            Button("Keep going", role: .cancel) { }
            Button("End & save") { focus.finish(context: context) }
        } message: { Text("Your focused time so far will be saved. Break time is not recorded.") }
    }
}
struct StudyTimeChart: View {
    let sessions: [StudySessionRecord]
    private var days: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 6, to: Calendar.current.startOfDay(for: Date())) } }
    var body: some View {
        Chart(days, id: \.self) { day in
            let minutes = sessions.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.durationSeconds } / 60
            BarMark(x: .value("Day", day, unit: .day), y: .value("Minutes", minutes)).foregroundStyle(Color.pilot).cornerRadius(1)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide))).accessibilityValue("\(Int(minutes)) minutes")
        }.chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .chartYAxisLabel("minutes").chartYScale(domain: 0...max(30, days.map { day in sessions.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.durationSeconds } / 60 }.max() ?? 30))
    }
}
