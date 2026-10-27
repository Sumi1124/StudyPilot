import SwiftUI
import StudyPilotCore

struct DailyStudyGoalView: View {
    let sessions: [StudySessionRecord]
    let now: Date
    var editable = false
    @AppStorage("dailyStudyGoalMinutes") private var goalMinutes = 60
    var body: some View {
        let progress = DailyStudyProgress(sessions: sessions, goalMinutes: goalMinutes, now: now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(progress.minutes)").font(.system(size: 28, weight: .medium)).monospacedDigit()
                Text("of \(progress.goalMinutes) min").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fraction)
                .accessibilityLabel("Daily study goal").accessibilityValue("\(progress.minutes) of \(progress.goalMinutes) minutes saved today")
            Text(progress.reachedGoal ? "Daily goal reached" : "\(progress.remainingMinutes) min remaining").font(.caption).foregroundStyle(.secondary)
            if editable {
                Stepper("Daily goal: \(progress.goalMinutes) min", value: Binding(get: { progress.goalMinutes }, set: { goalMinutes = $0 }), in: 15...480, step: 15).font(.caption)
                Text("Counts saved focus time.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
