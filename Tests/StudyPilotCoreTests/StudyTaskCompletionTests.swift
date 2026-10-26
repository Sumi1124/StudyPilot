import Testing
import Foundation
@testable import StudyPilotCore

@Test func finishingWaitsForTheEntireUndoWindowAndSurvivesRestart() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let value = CompletedStudyTask(title: "Quadratics", completedAt: now, needsCalendarAccess: true)
    #expect(!value.ready(at: now.addingTimeInterval(89.999)))
    #expect(value.ready(at: now.addingTimeInterval(90)))
    let restored = try JSONDecoder().decode(CompletedStudyTask.self, from: JSONEncoder().encode(value))
    #expect(restored == value && restored.ready(at: now.addingTimeInterval(1000)))
    var cleaned = value; cleaned.cleaned = true
    #expect(!cleaned.ready(at: now.addingTimeInterval(1000)))
}
@Test func linkedCleanupUsesExactTaskIdentityRegardlessOfTitleDateOrProgress() {
    let first = "local:" + UUID().uuidString, second = "local:" + UUID().uuidString
    let block = PlannedStudyBlock(taskID: first, title: "Same title", start: .distantPast, minutes: 25)
    let checked = StudyBlockTracking(completedAt: Date()).writing(to: block.notes)
    #expect(StudyTaskLink.matches(notes: block.notes, taskID: first))
    #expect(StudyTaskLink.matches(notes: checked, taskID: first))
    #expect(!StudyTaskLink.matches(notes: checked, taskID: second))
    #expect(!StudyTaskLink.matches(notes: "Same title", taskID: first))
    #expect(!StudyTaskLink.matches(notes: block.notes, taskID: ""))
}
@Test func syncedCleanupRequiresBothStudyPilotOwnershipAndExactTaskLink() {
    let task = "calendar:Google:deadline123"
    let block = PlannedStudyBlock(taskID: task, title: "Math", start: Date(), minutes: 25)
    #expect(StudyTaskLink.ownsSyncedSession(url: URL(string: "studypilot://plan/123"), notes: block.notes, taskID: task))
    #expect(!StudyTaskLink.ownsSyncedSession(url: nil, notes: block.notes, taskID: task))
    #expect(!StudyTaskLink.ownsSyncedSession(url: URL(string: "https://plan/123"), notes: block.notes, taskID: task))
    #expect(!StudyTaskLink.ownsSyncedSession(url: URL(string: "studypilot://other/123"), notes: block.notes, taskID: task))
    #expect(!StudyTaskLink.ownsSyncedSession(url: URL(string: "studypilot://plan/123"), notes: block.notes, taskID: "calendar:Google:deadline12"))
}
@Test func taskIdentityParsingDoesNotConfuseCalendarAndLocalAssignments() {
    let id = UUID()
    #expect(StudyTaskLink.localID("local:\(id.uuidString)") == id)
    #expect(StudyTaskLink.localID("calendar:\(id.uuidString)") == nil)
    #expect(StudyTaskLink.localID("local:not-a-uuid") == nil)
}
