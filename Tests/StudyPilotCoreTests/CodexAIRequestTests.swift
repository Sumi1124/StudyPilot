import Foundation
import Testing
@testable import StudyPilotCore

@Test func codexProviderDoesNotIncludeEarlierMessagesOrAttachments() throws {
    let messages = [StudyChatMessage(role: "user", text: "PRIVATE EARLIER CHAT", context: "PRIVATE EARLIER NOTE"),
                    StudyChatMessage(role: "assistant", text: "PRIVATE EARLIER ANSWER"),
                    StudyChatMessage(role: "user", text: "Estimate revision time", context: "EXPLICIT CURRENT ATTACHMENT")]
    let selected = CodexAIRequest.currentMessage(in: messages)
    let prompt = try StudyChat.prompt(messages: selected, calendarSnapshot: nil, studySnapshot: nil)
    #expect(selected.count == 1)
    #expect(!prompt.contains("PRIVATE EARLIER"))
    #expect(prompt.contains("EXPLICIT CURRENT ATTACHMENT"))
    #expect(ChatModelChoice.codex.historyFileName != ChatModelChoice.apple.historyFileName)
    #expect(ChatModelChoice.saved("codex") == .codex)
}

@Test func codexProviderRejectsUnsharedCalendarActions() throws {
    let move = #"{"reply":"Proposed move","eventID":"E1","start":"next-free"}"#
    for ids: [String]? in [nil, [], ["E2"]] {
        #expect(throws: (any Error).self) { try CodexAIRequest.chatReply(move, eventIDs: ids) }
    }
    let result = try CodexAIRequest.chatReply(move, eventIDs: ["E1"])
    #expect(result.move?.eventID == "E1")
    #expect(result.move?.start == nil)
    #expect(throws: (any Error).self) {
        try CodexAIRequest.chatReply(#"{"reply":"Move","eventID":"E1","start":"invalid"}"#, eventIDs: ["E1"])
    }
    #expect(try CodexAIRequest.chatReply(#"{"reply":"Hello","eventID":"none","start":""}"#, eventIDs: nil).move == nil)
}
