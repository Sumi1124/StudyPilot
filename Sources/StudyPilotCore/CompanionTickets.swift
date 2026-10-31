import Foundation

public struct CompanionTickets: Equatable, Sendable {
    public static let secondsPerTicket = 25 * 60
    public let earned: Int
    public let spent: Int
    public let secondsTowardsNext: Double

    public init(sessions: [StudySessionRecord], spent: Int) {
        let seconds = sessions.reduce(0.0) { total, session in
            guard session.completed, session.durationSeconds.isFinite, session.durationSeconds > 0 else { return total }
            return total + session.durationSeconds
        }
        let ticketCount = floor(seconds / Double(Self.secondsPerTicket))
        earned = ticketCount >= Double(Int.max) ? Int.max : Int(ticketCount)
        self.spent = max(0, spent)
        secondsTowardsNext = seconds.isFinite ? seconds.truncatingRemainder(dividingBy: Double(Self.secondsPerTicket)) : 0
    }

    public var balance: Int { max(0, earned - spent) }
    public var minutesUntilNext: Int {
        Int(ceil((Double(Self.secondsPerTicket) - secondsTowardsNext) / 60))
    }
}
