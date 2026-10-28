import Foundation
import Testing
@testable import StudyPilotCore

private func envelope(_ fields: [String: Any], model: String = OllamaWire.model, done: Bool = true, reason: String = "stop") throws -> Data {
    let content = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: ["model": model, "message": ["role": "assistant", "content": content], "done": done, "done_reason": reason])
}
@Test func modelPreferenceHasStableDefaultAndExactSelection() {
    #expect(ChatModelChoice.saved(nil) == .apple)
    #expect(ChatModelChoice.saved("unknown") == .apple)
    #expect(ChatModelChoice.saved("qwen08") == .qwen08)
}
@Test func localModelListRequiresExactInstalledTag() throws {
    #expect(try !OllamaWire.installed(in: Data(#"{"models":[{"name":"qwen3.5:9b"},{"name":"qwen3.5:0.8b"}]}"#.utf8)))
    #expect(try OllamaWire.installed(in: JSONSerialization.data(withJSONObject: ["models": [["name": OllamaWire.model]]])))
    #expect(try OllamaWire.installed(in: JSONSerialization.data(withJSONObject: ["models": [["model": OllamaWire.model]]])))
    #expect(try !OllamaWire.installed(in: Data(#"{"models":[]}"#.utf8)))
    #expect(throws: (any Error).self) { try OllamaWire.installed(in: Data(#"{}"#.utf8)) }
}
@Test func localRequestUsesLoopbackExactModelAndConstrainedActions() throws {
    #expect(OllamaWire.base.host == "127.0.0.1")
    let request = try #require(JSONSerialization.jsonObject(with: OllamaWire.requestBody(prompt: "hello", eventIDs: ["E2", "E1"])) as? [String: Any])
    #expect(request["model"] as? String == OllamaWire.model)
    #expect(request["stream"] as? Bool == false)
    #expect(request["think"] as? Bool == false)
    let format = try #require(request["format"] as? [String: Any])
    let properties = try #require(format["properties"] as? [String: [String: Any]])
    #expect(properties["eventID"]?["enum"] as? [String] == ["none", "E1", "E2"])
    for ids: [String]? in [nil, []] {
        let req = try #require(JSONSerialization.jsonObject(with: OllamaWire.requestBody(prompt: "hello", eventIDs: ids)) as? [String: Any])
        let schema = try #require(req["format"] as? [String: Any])
        let props = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(props["eventID"]?["enum"] as? [String] == ["none"])
    }
    #expect(throws: (any Error).self) { try OllamaWire.requestBody(prompt: String(repeating: "a", count: 20_001), eventIDs: nil) }
}
@Test func localRepliesKeepAnswersAndValidateCalendarAliases() throws {
    let normal = try OllamaWire.reply(from: envelope(["reply": "Hello", "eventID": "none", "start": ""]), eventIDs: nil)
    #expect(normal.reply == "Hello"); #expect(normal.move == nil)
    let exact = try OllamaWire.reply(from: envelope(["reply": "Proposed move", "eventID": "E1", "start": "2026-11-01 17:00"]), eventIDs: ["E1"])
    #expect(exact.move?.eventID == "E1"); #expect(exact.move?.start == "2026-11-01 17:00")
    let free = try OllamaWire.reply(from: envelope(["reply": "Find a slot", "eventID": "E1", "start": "next-free"]), eventIDs: ["E1"])
    #expect(free.move != nil); #expect(free.move?.start == nil)
    for ids: [String]? in [nil, [], ["E2"]] {
        #expect(throws: (any Error).self) { try OllamaWire.reply(from: envelope(["reply": "Move", "eventID": "E1", "start": "2026-11-01 17:00"]), eventIDs: ids) }
    }
}
@Test func localRepliesRejectMalformedTruncatedWrongModelAndEmptyAnswers() throws {
    let valid: [String: Any] = ["reply": "Hello", "eventID": "none", "start": ""]
    for data in [try envelope(valid, model: "qwen3.5:9b"), try envelope(valid, done: false), try envelope(valid, reason: "length"), try envelope(["reply": "", "eventID": "none", "start": ""]), Data("not json".utf8), Data(repeating: 1, count: 128_001)] {
        #expect(throws: (any Error).self) { try OllamaWire.reply(from: data, eventIDs: nil) }
    }
    for start in ["", "tomorrow", "2026-99-01 17:00"] {
        #expect(throws: (any Error).self) { try OllamaWire.reply(from: envelope(["reply": "Proposed", "eventID": "E1", "start": start]), eventIDs: ["E1"]) }
    }
}
@Test func localDownloadProgressClampsAndHandlesMissingSizes() throws {
    let decode: (String) throws -> OllamaWire.Progress = { try JSONDecoder().decode(OllamaWire.Progress.self, from: Data($0.utf8)) }
    #expect(try decode(#"{"total":100,"completed":25}"#).fraction == 0.25)
    #expect(try decode(#"{"total":100,"completed":150}"#).fraction == 1)
    #expect(try decode(#"{"total":100,"completed":-1}"#).fraction == 0)
    #expect(try decode(#"{"status":"verifying"}"#).fraction == nil)
    #expect(try decode(#"{"total":0,"completed":0}"#).fraction == nil)
}
@Test func savedChatsSupportLegacyAndSelectedModelLabels() throws {
    var thread = StudyChatThread()
    thread.messages = [.init(role: "user", text: "Hello"), .init(role: "assistant", text: "Hi", answerKind: "ai", model: ChatModelChoice.qwen08.title)]
    let data = try JSONEncoder().encode([thread])
    #expect(try StudyChat.decode(data).first?.messages.last?.model == ChatModelChoice.qwen08.title)
    var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    var messages = try #require(legacy[0]["messages"] as? [[String: Any]])
    messages[1].removeValue(forKey: "model"); legacy[0]["messages"] = messages
    #expect(try StudyChat.decode(JSONSerialization.data(withJSONObject: legacy)).first?.messages.last?.model == nil)
}
