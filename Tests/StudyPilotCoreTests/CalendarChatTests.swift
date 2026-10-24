import Foundation
import Testing
@testable import StudyPilotCore

private var chatCalendar: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
private func chatDate(_ text: String) throws -> Date { try CalendarChat.date(text, calendar: chatCalendar) }
private func chatEvent() throws -> CalendarChatEvent {
    .init(id: "local:math", title: "Math study", start: try chatDate("2026-10-24 16:00"), end: try chatDate("2026-10-24 16:25"), source: "StudyPilot", movable: true, deadline: try chatDate("2026-10-26 12:00"))
}
@Test func calendarChatDecodesAnswersAndExplicitOrAutomaticMoveProposals() throws {
    let answer = try CalendarChatResponse.decode("{\"reply\":\"You have Math at 4pm.\",\"move\":null}")
    #expect(answer.move == nil)
    let move = try CalendarChatResponse.decode("```json\n{\"reply\":\"Proposed move\",\"move\":{\"eventID\":\"E1\",\"start\":\"2026-10-25 17:00\"}}\n```")
    #expect(move.move?.eventID == "E1"); #expect(move.move?.start == "2026-10-25 17:00")
    let auto = try CalendarChatResponse.decode("{\"reply\":\"Find free time\",\"move\":{\"eventID\":\"E1\",\"start\":null}}")
    #expect(auto.move != nil); #expect(auto.move?.start == nil)
}
@Test func calendarChatRejectsMalformedAndOversizedActions() {
    for text in ["Moved your calendar", "{}", "{\"reply\":\"\"}", "{\"reply\":\"Hi\",\"move\":{\"eventID\":\"\"}}", "{\"reply\":\"Hi\",\"move\":{\"eventID\":\"E1\",\"start\":\"not a real date with more than 16 chars\"}}"] {
        #expect(throws: (any Error).self) { try CalendarChatResponse.decode(text) }
    }
}
@Test func calendarChatValidatesExactDatesAndDSTGaps() throws {
    #expect(try chatDate("2026-10-25 17:00") < chatDate("2026-10-25 18:00"))
    for value in ["tomorrow", "2026-02-30 17:00", "2026-10-25 25:00", "2026-10-25T17:00Z"] {
        #expect(throws: (any Error).self) { try chatDate(value) }
    }
    var cal = chatCalendar; cal.timeZone = TimeZone(identifier: "America/New_York")!
    #expect(throws: (any Error).self) { try CalendarChat.date("2026-03-08 02:30", calendar: cal) }
}
@Test func calendarMoveRejectsConflictsPastTimesAndDeadlineChanges() throws {
    let event = try chatEvent(), now = try chatDate("2026-10-24 10:00"), next = try chatDate("2026-10-25 17:00")
    try CalendarChat.validateMove(event, to: next, busy: [], now: now)
    let clash = PlanningBusyTime(start: next.addingTimeInterval(600), end: next.addingTimeInterval(1800))
    #expect(throws: (any Error).self) { try CalendarChat.validateMove(event, to: next, busy: [clash], now: now) }
    #expect(throws: (any Error).self) { try CalendarChat.validateMove(event, to: now, busy: [], now: now) }
    #expect(throws: (any Error).self) { try CalendarChat.validateMove(event, to: chatDate("2026-10-26 11:50"), busy: [], now: now) }
    var readOnly = event; readOnly.movable = false
    #expect(throws: (any Error).self) { try CalendarChat.validateMove(readOnly, to: next, busy: [], now: now) }
}
@Test func calendarSummaryUsesCurrentSnapshotAliasesAndReportsOmissions() throws {
    let event = try chatEvent(), now = try chatDate("2026-10-24 10:00"), range = DateInterval(start: now, duration: 7 * 86_400)
    let items = (0..<100).map { index in var copy = event; copy.id = "event:\(index)"; copy.title = "数学 \(index)"; return copy }
    let (summary, aliases) = try CalendarChat.summary(events: items, range: range, now: now, calendar: chatCalendar)
    #expect(aliases["E1"]?.id == "event:0"); #expect(aliases.count < items.count)
    #expect(summary.utf8.count < 3700); #expect(summary.contains("omitted")); #expect(summary.contains("2026-10-24 10:00"))
    let prompt = try StudyChat.prompt(messages: [.init(role: "user", text: "What is planned?")], calendarSnapshot: summary)
    #expect(prompt.contains(summary)); #expect(prompt.contains("What is planned?"))
}
