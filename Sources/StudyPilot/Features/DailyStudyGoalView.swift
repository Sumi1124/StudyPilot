import SwiftUI
import StudyPilotCore

struct DailyStudyGoalView: View {
    let sessions: [StudySessionRecord]
    let now: Date
    var editable = false
    @AppStorage("dailyStudyGoalMinutes") private var goalMinutes = 60

    var body: some View {
        let progress = DailyStudyProgress(sessions: sessions, goalMinutes: goalMinutes, now: now)
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.pilot.opacity(0.12), lineWidth: 10)
                Circle().trim(from: 0, to: progress.fraction)
                    .stroke(Color.pilot, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text("\(progress.minutes)").font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("of \(progress.goalMinutes) min").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 120, height: 120).padding(5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Daily study goal")
                .accessibilityValue("\(progress.minutes) of \(progress.goalMinutes) minutes saved today")
            Text(progress.reachedGoal ? "Daily goal reached" : "\(progress.remainingMinutes) min to your daily goal")
                .font(.caption.weight(.medium)).foregroundStyle(Color.pilot)
            if editable {
                Stepper("Daily goal: \(progress.goalMinutes) min", value: Binding(
                    get: { progress.goalMinutes }, set: { goalMinutes = $0 }
                ), in: 15...480, step: 15).font(.caption)
                Text("Counts saved focus time. Adjust the goal to suit your day.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}
