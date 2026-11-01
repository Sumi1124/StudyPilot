import SwiftUI
import StudyPilotCore

private enum CompanionFood: String, CaseIterable, Identifiable {
    case apple, onigiri, toast
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .apple: "🍎"
        case .onigiri: "🍙"
        case .toast: "🍞"
        }
    }
}

private enum CompanionReaction: Equatable {
    case eating(CompanionFood), playing, resting
}

struct StudyCompanionView: View {
    let sessions: [StudySessionRecord]
    @Environment(AppState.self) private var app
    @Environment(FocusController.self) private var focus
    @AppStorage("companionName") private var name = "Mochi"
    @AppStorage("companionSnackAt") private var snackAt = 0.0
    @AppStorage("companionPlayAt") private var playAt = 0.0
    @AppStorage("companionRestAt") private var restAt = 0.0
    @AppStorage("companionTicketsSpent") private var ticketsSpent = 0
    @State private var reaction: CompanionReaction?

    private var displayName: String { name.isEmpty ? "Mochi" : name }
    private var completed: Int { sessions.filter { $0.completed && $0.durationSeconds >= 300 }.count }
    private var tickets: CompanionTickets { CompanionTickets(sessions: sessions, spent: ticketsSpent) }
    private var stage: String { completed >= 20 ? "Study buddy" : completed >= 5 ? "Explorer" : "Hatchling" }
    private var nextMilestone: Int { completed < 5 ? 5 : 20 }
    private var focusIsRunning: Bool { focus.state?.isBreak == false }

    private func level(_ timestamp: Double) -> Double {
        guard timestamp > 0 else { return 0.45 }
        return max(0.12, 1 - max(0, app.now.timeIntervalSince1970 - timestamp) / 172_800)
    }
    private var mood: String {
        switch reaction {
        case .eating(let food): return "Loved that \(food.title.lowercased())!"
        case .playing: return "That was fun!"
        case .resting: return "Feeling cozy now"
        case nil: break
        }
        if focusIsRunning { return "Cheering on your focus session" }
        if level(snackAt) < 0.25 { return "Could use a little snack" }
        if level(playAt) < 0.25 { return "Ready for a short play break" }
        if level(restAt) < 0.25 { return "Ready to rest" }
        return "Happy to study alongside you"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            creature.frame(width: 170, height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(displayName), \(stage), \(mood)")
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName).font(.title2.weight(.semibold))
                        Text("\(stage) · \(mood)").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Label("\(tickets.balance) \(tickets.balance == 1 ? "ticket" : "tickets")", systemImage: "ticket.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.pilot)
                        Text("\(completed) focus \(completed == 1 ? "session" : "sessions")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: tickets.secondsTowardsNext, total: Double(CompanionTickets.secondsPerTicket))
                        .tint(Color.pilot)
                        .accessibilityLabel("Progress toward next food ticket")
                        .accessibilityValue("\(tickets.minutesUntilNext) minutes remaining")
                    Text("\(tickets.minutesUntilNext) min of completed focus until the next ticket · 25 min earns 1")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    need("Snack", value: level(snackAt), symbol: "carrot.fill")
                    need("Play", value: level(playAt), symbol: "sparkles")
                    need("Rest", value: level(restAt), symbol: "moon.stars.fill")
                }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(CompanionFood.allCases) { food in
                            Button("\(food.emoji) \(food.title) · 1 ticket") { feed(food) }
                        }
                    } label: {
                        Label("Choose food · 1 ticket", systemImage: "fork.knife")
                    }.disabled(tickets.balance == 0)
                        .help(tickets.balance == 0 ? "Complete focus time to earn a food ticket." : "Choose a snack for one ticket.")
                    Button("Play", systemImage: "sparkles") {
                        playAt = Date().timeIntervalSince1970
                        reaction = .playing
                    }
                    Button("Rest", systemImage: "moon.stars") {
                        restAt = Date().timeIntervalSince1970
                        reaction = .resting
                    }
                    Spacer(minLength: 4)
                    if completed < nextMilestone {
                        let remaining = nextMilestone - completed
                        Text("\(remaining) \(remaining == 1 ? "session" : "sessions") until \(completed < 5 ? "Explorer" : "Study buddy")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.bordered)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).pilotCard()
            .task(id: reaction) {
                guard reaction != nil else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                reaction = nil
            }
    }

    private func feed(_ food: CompanionFood) {
        guard tickets.balance > 0 else { return }
        ticketsSpent = max(0, ticketsSpent) + 1
        snackAt = Date().timeIntervalSince1970
        reaction = .eating(food)
    }

    private func need(_ title: String, value: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption)
            ProgressView(value: value).tint(Color.pilot).accessibilityLabel("\(title) level")
        }.frame(maxWidth: .infinity)
    }

    private var creature: some View {
        ZStack {
            Circle().fill(Color.pilot.opacity(0.09)).frame(width: 160, height: 160)
            Circle().stroke(Color.pilot.opacity(0.17), lineWidth: 1).frame(width: 160, height: 160)
            if completed >= 5 {
                HStack(spacing: 66) {
                    Ellipse().fill(Color.pilot.opacity(0.44)).frame(width: 24, height: 42).rotationEffect(.degrees(-26))
                    Ellipse().fill(Color.pilot.opacity(0.44)).frame(width: 24, height: 42).rotationEffect(.degrees(26))
                }.offset(y: -56)
            }
            Ellipse().fill(Color.pilot.opacity(0.28)).frame(width: 112, height: 122)
                .overlay(Ellipse().stroke(Color.pilot.opacity(0.5), lineWidth: 2))
            Ellipse().fill(Color(nsColor: .windowBackgroundColor).opacity(0.77))
                .frame(width: 78, height: 56).offset(y: 27)
            if reaction == .resting {
                HStack(spacing: 26) {
                    Capsule().fill(Color.primary).frame(width: 17, height: 3)
                    Capsule().fill(Color.primary).frame(width: 17, height: 3)
                }.offset(y: -11)
            } else {
                HStack(spacing: 27) {
                    Circle().fill(Color.primary).frame(width: 8, height: 8)
                    Circle().fill(Color.primary).frame(width: 8, height: 8)
                }.offset(y: -11)
            }
            if completed >= 20 {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 5).stroke(Color.pilot, lineWidth: 2).frame(width: 24, height: 18)
                    Capsule().fill(Color.pilot).frame(width: 7, height: 2)
                    RoundedRectangle(cornerRadius: 5).stroke(Color.pilot, lineWidth: 2).frame(width: 24, height: 18)
                }.offset(y: -11)
            }
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.pilot).offset(y: 9)
            HStack(spacing: 92) {
                Ellipse().fill(Color.pink.opacity(0.4)).frame(width: 13, height: 8)
                Ellipse().fill(Color.pink.opacity(0.4)).frame(width: 13, height: 8)
            }.offset(y: 12)
            if completed >= 20 {
                Image(systemName: "book.closed.fill").font(.system(size: 19))
                    .foregroundStyle(Color.pilot).offset(y: 55)
            } else if completed >= 5 {
                Image(systemName: "leaf.fill").font(.system(size: 17))
                    .foregroundStyle(Color.pilot).offset(y: -66)
            }
            if case .eating(let food) = reaction {
                Text(food.emoji).font(.system(size: 27)).offset(x: 57, y: 43)
            }
            if reaction == .playing || focusIsRunning {
                Image(systemName: "sparkle").foregroundStyle(.yellow).offset(x: 60, y: -57)
            }
            if reaction == .resting {
                Text("z z").font(.caption2.weight(.semibold)).foregroundStyle(Color.pilot).offset(x: 58, y: -57)
            }
        }.scaleEffect(reaction == .playing ? 1.05 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: reaction)
    }
}
