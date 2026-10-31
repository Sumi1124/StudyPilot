import SwiftUI
import StudyPilotCore

struct StudyCompanionView: View {
    let sessions: [StudySessionRecord]
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @AppStorage("companionName") private var name = "Mochi"
    @AppStorage("companionSnackAt") private var snackAt = 0.0
    @AppStorage("companionPlayAt") private var playAt = 0.0
    @AppStorage("companionRestAt") private var restAt = 0.0

    private var completed: Int { sessions.filter { $0.completed && $0.durationSeconds >= 300 }.count }
    private var stage: String { completed >= 20 ? "Study buddy" : completed >= 5 ? "Explorer" : "Hatchling" }
    private var nextMilestone: Int { completed < 5 ? 5 : 20 }
    private func level(_ timestamp: Double) -> Double {
        guard timestamp > 0 else { return 0.45 }
        return max(0.12, 1 - max(0, app.now.timeIntervalSince1970 - timestamp) / 172_800)
    }
    private var mood: String {
        if focus.state?.isBreak == false { return "Cheering on your focus session" }
        if level(snackAt) < 0.25 { return "Could use a little snack" }
        if level(playAt) < 0.25 { return "Ready for a short play break" }
        if level(restAt) < 0.25 { return "Ready to rest" }
        return "Happy to study alongside you"
    }
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            creature.frame(width: 155, height: 155).accessibilityLabel("\(name), \(stage), \(mood)")
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.isEmpty ? "Mochi" : name).font(.title2.weight(.semibold))
                        Text("\(stage) · \(mood)").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(completed) focus sessions").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    need("Snack", value: level(snackAt), symbol: "carrot.fill")
                    need("Play", value: level(playAt), symbol: "sparkles")
                    need("Rest", value: level(restAt), symbol: "moon.stars.fill")
                }
                HStack {
                    Button("Give snack") { snackAt = Date().timeIntervalSince1970 }
                    Button("Play") { playAt = Date().timeIntervalSince1970 }
                    Button("Rest") { restAt = Date().timeIntervalSince1970 }
                    Spacer()
                    if completed < nextMilestone { Text("\(nextMilestone - completed) sessions until \(completed < 5 ? "Explorer" : "Study buddy")").font(.caption2).foregroundStyle(.secondary) }
                }.buttonStyle(.bordered)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).pilotCard()
    }
    private func need(_ title: String, value: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption)
            ProgressView(value: value).tint(Color.pilot)
        }.frame(maxWidth: .infinity)
    }
    private var creature: some View {
        ZStack {
            Circle().fill(Color.pilot.opacity(0.10)).frame(width: 146, height: 146)
            Ellipse().fill(Color.pilot.opacity(0.24)).frame(width: 108, height: 116)
                .overlay(Ellipse().stroke(Color.pilot.opacity(0.42), lineWidth: 2))
            Ellipse().fill(Color(nsColor: .windowBackgroundColor).opacity(0.75)).frame(width: 72, height: 52).offset(y: 25)
            HStack(spacing: 29) {
                Circle().fill(Color.primary).frame(width: 8, height: 8)
                Circle().fill(Color.primary).frame(width: 8, height: 8)
            }.offset(y: -10)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pilot).offset(y: 8)
            HStack(spacing: 89) {
                Circle().fill(Color.pink.opacity(0.45)).frame(width: 13, height: 8)
                Circle().fill(Color.pink.opacity(0.45)).frame(width: 13, height: 8)
            }.offset(y: 11)
            if focus.state?.isBreak == false { Image(systemName: "sparkle").foregroundStyle(.yellow).offset(x: 57, y: -58) }
        }
    }
}
