import Foundation
import StudyPilotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Guided generation separates natural replies from a small, validated calendar action.
/// The model can only select an event alias supplied by the current request.
@MainActor enum StudyChatGeneration {
    static func reply(to prompt: String, eventIDs: [String]?) async throws -> CalendarChatResponse {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if let eventIDs {
                let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "StudyChatReply", properties: [
                    .init(name: "eventID", description: "Use none for questions, tutoring, finding tasks, or ambiguous moves. Only choose an E-ID if the user asks to move that specific event, including a clear follow-up like move it. Never select an assignment deadline.", schema: DynamicGenerationSchema(name: "EventChoice", anyOf: ["none"] + eventIDs.sorted())),
                    .init(name: "start", description: "Empty string if eventID is none. Otherwise local yyyy-MM-dd HH:mm for the requested new time, or next-free only when the user asks for the next available study slot. Resolve tomorrow using the current date.", schema: DynamicGenerationSchema(type: String.self)),
                    .init(name: "reply", description: "A natural, helpful reply to the latest user message. Use real task titles and subject links. Recognize topics as their subjects and report only matching saved items. For moves describe a proposal, never claim it was applied. Do not expose IDs or output formatting.", schema: DynamicGenerationSchema(type: String.self))
                ]), dependencies: [])
                let session = LanguageModelSession(instructions: CalendarChat.instructions)
                let response = try await session.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: 0.15, maximumResponseTokens: 800))
                let reply: String = try response.content.value(forProperty: "reply")
                let eventID: String = try response.content.value(forProperty: "eventID")
                let start: String = try response.content.value(forProperty: "start")
                var value: [String: Any] = ["reply": reply, "move": NSNull()]
                if eventID != "none" {
                    guard eventIDs.contains(eventID), !start.isEmpty else {
                        value["reply"] = reply + (eventIDs.isEmpty ? "" : "\n\nNo change is prepared yet. Please specify the event and its new time, or ask for the next free slot.")
                        return try CalendarChatResponse.decode(String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self))
                    }
                    value["move"] = ["eventID": eventID, "start": start == "next-free" ? NSNull() : start] as [String: Any]
                }
                let data = try JSONSerialization.data(withJSONObject: value)
                return try CalendarChatResponse.decode(String(decoding: data, as: UTF8.self))
            }
            let response = try await LanguageModelSession(instructions: StudyChat.instructions).respond(to: prompt, options: GenerationOptions(temperature: 0.35, maximumResponseTokens: 800))
            let data = try JSONSerialization.data(withJSONObject: ["reply": response.content, "move": NSNull()])
            return try CalendarChatResponse.decode(String(decoding: data, as: UTF8.self))
        }
        #endif
        throw PlanningError.invalid("AI chat requires macOS 26 with Apple Intelligence enabled.")
    }
}
