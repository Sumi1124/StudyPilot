import Foundation
import Testing
@testable import StudyPilotCore

@Test func completedFocusTimeEarnsTicketsAcrossSessions() {
    let sessions = [
        StudySessionRecord(durationSeconds: 600, completed: true),
        StudySessionRecord(durationSeconds: 1_200, completed: true),
        StudySessionRecord(durationSeconds: 1_500, completed: false),
    ]
    let tickets = CompanionTickets(sessions: sessions, spent: 1)
    #expect(tickets.earned == 1)
    #expect(tickets.balance == 0)
    #expect(tickets.secondsTowardsNext == 300)
    #expect(tickets.minutesUntilNext == 20)
    #expect(CompanionTickets(sessions: sessions, spent: 0).balance == 1)
}

@Test func foodTicketsIgnoreInvalidTimeAndNeverShowNegativeBalance() {
    let sessions = [
        StudySessionRecord(durationSeconds: 1_500, completed: true),
        StudySessionRecord(durationSeconds: -.infinity, completed: true),
        StudySessionRecord(durationSeconds: -60, completed: true),
    ]
    #expect(CompanionTickets(sessions: sessions, spent: 8).balance == 0)
    #expect(CompanionTickets(sessions: sessions, spent: -1).balance == 1)
    #expect(CompanionTickets(sessions: sessions, spent: 0).minutesUntilNext == 25)
}
