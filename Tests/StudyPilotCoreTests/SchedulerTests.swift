import Testing
import Foundation
@testable import StudyPilotCore

private let instant = Date(timeIntervalSince1970: 1_700_000_000)
private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }

@Test func firstGoodAndSecondGoodReview() {
    let card = FlashcardRecord(deckID: UUID(), question: "Q", answer: "A")
    let first = ReviewScheduler.schedule(card, rating: .good, now: instant, calendar: utc)
    #expect(first.intervalDays == 1 && first.repetitions == 1)
    let second = ReviewScheduler.schedule(first, rating: .good, now: first.dueDate, calendar: utc)
    #expect(second.intervalDays == 3 && second.repetitions == 2)
    let third = ReviewScheduler.schedule(second, rating: .good, now: second.dueDate, calendar: utc)
    #expect(third.intervalDays == 8)
}
@Test func failedReviewResetsAndRetriesInTenMinutes() {
    let card = FlashcardRecord(intervalDays: 50, ease: 1.3, repetitions: 9, lapses: 2)
    let result = ReviewScheduler.schedule(card, rating: .again, now: instant)
    #expect(result.repetitions == 0 && result.intervalDays == 0)
    #expect(result.lapses == 3 && result.ease == 1.3)
    #expect(result.dueDate.timeIntervalSince(instant) == 600)
}
@Test func hardAndEasyHaveBoundedEaseAndIntervals() {
    let hard = ReviewScheduler.schedule(FlashcardRecord(intervalDays: 10, ease: 1.3, repetitions: 3), rating: .hard, now: instant)
    #expect(hard.intervalDays == 12 && hard.ease == 1.3)
    let easy = ReviewScheduler.schedule(FlashcardRecord(intervalDays: 36_500, ease: 3, repetitions: 100), rating: .easy, now: instant)
    #expect(easy.intervalDays == 36_500 && easy.ease == 3)
    #expect(ReviewScheduler.schedule(FlashcardRecord(), rating: .easy, now: instant).intervalDays == 4)
}
@Test func schedulingIsDeterministicAndHandlesDaylightSaving() {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
    let beforeDST = c.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
    let card = FlashcardRecord()
    let result = ReviewScheduler.schedule(card, rating: .good, now: beforeDST, calendar: c)
    #expect(result == ReviewScheduler.schedule(card, rating: .good, now: beforeDST, calendar: c))
    #expect(c.component(.hour, from: result.dueDate) == 12)
    #expect(result.dueDate.timeIntervalSince(beforeDST) == 23 * 3600)
}
@Test func reviewAccuracyUsesRealHistory() {
    #expect(ReviewScheduler.accuracy([]) == nil)
    let history = [ReviewRecord(rating: "Again"), ReviewRecord(rating: "Hard"), ReviewRecord(rating: "Good"), ReviewRecord(rating: "Easy")]
    #expect(ReviewScheduler.accuracy(history) == 0.75)
}
@Test func timerSurvivesPausesAndSerialization() throws {
    var timer = FocusState(subjectID: UUID(), seconds: 1500, now: instant)
    timer.pause(at: instant.addingTimeInterval(300))
    #expect(timer.remaining(at: instant.addingTimeInterval(6000)) == 1200)
    timer.resume(at: instant.addingTimeInterval(8000))
    let recovered = try JSONDecoder().decode(FocusState.self, from: JSONEncoder().encode(timer))
    #expect(recovered.id == timer.id)
    #expect(recovered.remaining(at: instant.addingTimeInterval(8600)) == 600)
    #expect(recovered.remaining(at: instant.addingTimeInterval(20_000)) == 0)
    #expect(recovered.elapsed(at: instant.addingTimeInterval(20_000)) == 1500)
    #expect(recovered.completionDate == instant.addingTimeInterval(9200))
}
@Test func timerClampsDurationsAndBackwardClockChanges() {
    let timer = FocusState(subjectID: nil, seconds: -10, now: instant)
    #expect(timer.plannedSeconds == 60)
    #expect(timer.remaining(at: instant.addingTimeInterval(-600)) == 60)
    #expect(FocusState(subjectID: nil, seconds: 99_999, now: instant).plannedSeconds == 14_400)
}
@Test func streakCountsUniqueDaysAndIncludesYesterday() {
    let c = utc; let today = c.startOfDay(for: instant)
    func session(_ daysAgo: Int, _ seconds: Double = 60) -> StudySessionRecord { StudySessionRecord(endedAt: today.addingTimeInterval(Double(-daysAgo) * 86_400 + 3600), durationSeconds: seconds) }
    #expect(StudyAnalytics.streak(sessions: [], now: instant, calendar: c) == 0)
    #expect(StudyAnalytics.streak(sessions: [session(0), session(0), session(1), session(2)], now: instant, calendar: c) == 3)
    #expect(StudyAnalytics.streak(sessions: [session(1), session(2)], now: instant, calendar: c) == 2)
    #expect(StudyAnalytics.streak(sessions: [session(2)], now: instant, calendar: c) == 0)
    #expect(StudyAnalytics.streak(sessions: [session(0, 59)], now: instant, calendar: c) == 0)
}
@Test func criterionAveragesKeepZeroAndIgnoreMissing() {
    let subject = UUID()
    let results = [AssessmentRecord(subjectID: subject, criterionA: 0, criterionB: 8), AssessmentRecord(subjectID: subject, criterionA: 8)]
    #expect(StudyAnalytics.average(.a, assessments: results) == 4)
    #expect(StudyAnalytics.average(.b, assessments: results) == 8)
    #expect(StudyAnalytics.average(.c, assessments: results) == nil)
}
@Test func wikiLinksAreUniqueTrimmedAndIgnoreBrokenSyntax() {
    #expect(NoteLinks.titles(in: "[[ Algebra ]] and [[Algebra]] and [[Geometry]] and [[unfinished") == ["Algebra", "Geometry"])
}
