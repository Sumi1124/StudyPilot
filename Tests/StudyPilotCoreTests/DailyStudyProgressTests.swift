import Testing
import Foundation
@testable import StudyPilotCore

@Test func dailyProgressUsesLocalEndingDayAndExcludesFutureSessions() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 1))!
    let sessions = [
        StudySessionRecord(endedAt: now.addingTimeInterval(-60), durationSeconds: 1500),
        StudySessionRecord(endedAt: now.addingTimeInterval(-7200), durationSeconds: 3000),
        StudySessionRecord(endedAt: now.addingTimeInterval(60), durationSeconds: 900),
        StudySessionRecord(endedAt: now, durationSeconds: 35, completed: false)
    ]
    let progress = DailyStudyProgress(sessions: sessions, goalMinutes: 30, now: now, calendar: calendar)
    #expect(progress.seconds == 1535)
    #expect(progress.minutes == 25)
    #expect(progress.remainingMinutes == 5)
    #expect(!progress.reachedGoal)
}

@Test func dailyGoalCapsRingButKeepsEarnedTimeAndBoundsPreferences() {
    let now = Date()
    let progress = DailyStudyProgress(sessions: [.init(endedAt: now, durationSeconds: 5400)], goalMinutes: 60, now: now)
    #expect(progress.minutes == 90)
    #expect(progress.fraction == 1)
    #expect(progress.reachedGoal)
    #expect(progress.remainingMinutes == 0)
    #expect(DailyStudyProgress(sessions: [], goalMinutes: 0, now: now).goalMinutes == 15)
    #expect(DailyStudyProgress(sessions: [], goalMinutes: 999, now: now).goalMinutes == 480)
}
