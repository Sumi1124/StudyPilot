import Foundation
import Testing
@testable import StudyPilotCore

private func effortJSON(low: Int = 25, likely: Int = 45, high: Int = 75, reason: String = "Several unfamiliar exercises need focused work.") throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["scope": "Twelve short exercises remain.", "minimumMinutes": low, "minutes": likely, "maximumMinutes": high, "reason": reason]), as: UTF8.self)
}
@Test func timeEstimatesValidateOrderedBoundsAndRoundUpToFiveMinutes() throws {
    let value = try EffortEstimate.decode(effortJSON(low: 6, likely: 31, high: 61))
    #expect(value.minimumMinutes == 10); #expect(value.minutes == 35); #expect(value.maximumMinutes == 65)
    #expect(try EffortEstimate.decode(effortJSON(low: 5, likely: 1440, high: 1440)).minutes == 1440)
    for values in [(0,30,60), (30,20,60), (20,60,50), (10,30,1441), (-1,0,5)] {
        #expect(throws: (any Error).self) { try EffortEstimate.decode(effortJSON(low: values.0, likely: values.1, high: values.2)) }
    }
}
@Test func timeEstimatesRejectMalformedUnboundedAndMissingExplanations() throws {
    for text in ["not json", "{}", try effortJSON(reason: " "), try effortJSON(reason: String(repeating: "a", count: 501)), String(repeating: "a", count: 10_001), #"{"scope":"Some remaining work","minimumMinutes":10,"minutes":12.5,"maximumMinutes":30,"reason":"x","assumption":"y"}"#] {
        #expect(throws: (any Error).self) { try EffortEstimate.decode(text) }
    }
}
@Test func estimateContextUsesRemainingChecklistAndStudentScopeWithoutCompletedAnswers() throws {
    var input = EffortEstimateInput(id: "test", title: "Quadratic equations", details: "Exercises 1–12", subject: "Mathematics", deadline: Date(timeIntervalSince1970: 0), checklist: [.init(title: "Already completed secret", isComplete: true), .init(title: "Remaining exercises")])
    input.familiarity = .newTopic; input.workLeft = "Six exercises left"
    let prompt = try input.prompt()
    #expect(prompt.contains("Mathematics")); #expect(prompt.contains("Six exercises left")); #expect(prompt.contains("New to this topic"))
    #expect(prompt.contains("Remaining exercises")); #expect(!prompt.contains("Already completed secret"))
    #expect(prompt.contains("\"completedChecklistCount\":1")); #expect(prompt.contains("\"remainingChecklistCount\":1"))
    #expect(EffortEstimation.instructions.contains("Do not shrink the work to fit the deadline"))
    #expect(EffortEstimation.instructions.contains("Future booked study sessions are still work left"))
    #expect(input.basisNote.contains("Uses your description of work left"))
    #expect(input.basisNote.contains("New to this topic"))
    #expect(!input.basisNote.contains("wasn't specified"))
    input.workLeft = ""; input.familiarity = .unspecified
    #expect(input.basisNote.contains("saved task details")); #expect(input.basisNote.contains("Familiarity wasn't specified"))
    input.completed = true
    #expect(!input.canEstimate); #expect(throws: (any Error).self) { try input.prompt() }
    input.completed = false; input.title = "   "
    #expect(!input.canEstimate); #expect(throws: (any Error).self) { try input.prompt() }
}
@Test func estimateContextIsBoundedAndDoesNotMutateTaskRecords() throws {
    let task = AssignmentRecord(title: String(repeating: "課", count: 1000), details: String(repeating: "題", count: 10_000), estimatedMinutes: 30, checklist: (0..<100).map { ChecklistItem(title: "Problem \($0)" + String(repeating: "a", count: 1000)) })
    let original = task
    let input = EffortEstimateInput(id: task.id.uuidString, title: task.title, details: task.details, subject: String(repeating: "学", count: 1000), deadline: task.dueDate, checklist: task.checklist)
    let prompt = try input.prompt()
    #expect(prompt.utf8.count < 6500)
    #expect(prompt.contains("\"omittedChecklistCount\":88"))
    let estimate = try EffortEstimate.decode(effortJSON())
    #expect(task == original); #expect(task.estimatedMinutes != estimate.minutes)
}
@Test func localEstimateRequestUsesSelectedLocalModelAndNoCalendarActionSchema() throws {
    let input = EffortEstimateInput(id: "test", title: "Essay draft", deadline: Date())
    let body = try #require(JSONSerialization.jsonObject(with: EffortEstimation.ollamaBody(input: input)) as? [String: Any])
    #expect(body["model"] as? String == OllamaWire.model); #expect(body["stream"] as? Bool == false); #expect(body["think"] as? Bool == false)
    let schema = try #require(body["format"] as? [String: Any]); let properties = try #require(schema["properties"] as? [String: Any])
    #expect(properties["minutes"] != nil); #expect(properties["eventID"] == nil); #expect(properties["steps"] == nil)
    #expect(properties.keys.count == 5)
}
