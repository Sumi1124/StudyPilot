import Foundation
import Observation
import StudyPilotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor @Observable final class StudyChatService {
    let calendar = CalendarChatService()
    var threads: [StudyChatThread] = []
    var selectedID: UUID?
    var generating = false
    var error: String?
    private var url: URL?
    private var loadFailed = false
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    var selected: StudyChatThread? { threads.first { $0.id == selectedID } }
    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in System Settings to use AI chat."
            case .unavailable(.modelNotReady): return "Apple’s on-device model is still preparing. Try again when it is ready."
            case .unavailable(.deviceNotEligible): return "This Mac does not support Apple’s on-device AI. Saved chats are still available."
            @unknown default: return "Apple’s on-device AI is currently unavailable."
            }
        }
        #endif
        return "AI chat requires macOS 26 and an Apple Intelligence compatible Mac."
    }
    func configure(folder: URL) {
        guard url == nil else { return }
        url = folder.appendingPathComponent("StudyChats.json")
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do { threads = try StudyChat.decode(Data(contentsOf: url)); selectedID = threads.first?.id }
        catch { loadFailed = true; self.error = "Your chat history could not be opened and has been preserved: \(error.localizedDescription)" }
    }
    private func save() throws {
        guard !loadFailed, let url else { throw PlanningError.invalid("Chat storage is unavailable. Your existing history has not been changed.") }
        let data = try JSONEncoder().encode(threads)
        _ = try StudyChat.decode(data)
        try data.write(to: url, options: .atomic)
    }
    func newChat() {
        guard !generating else { return }
        error = nil; calendar.pending = nil
        if let empty = threads.first(where: { $0.messages.isEmpty }) { selectedID = empty.id; return }
        guard threads.count < 50 else { error = "You have 50 saved chats. Delete a conversation before starting another."; return }
        let thread = StudyChatThread(); threads.insert(thread, at: 0); selectedID = thread.id
        do { try save() } catch { threads.removeAll { $0.id == thread.id }; selectedID = threads.first?.id; self.error = error.localizedDescription }
    }
    func deleteSelected() {
        guard !generating, let selectedID else { return }
        let previous = threads
        threads.removeAll { $0.id == selectedID }
        do { try save(); self.selectedID = threads.first?.id; error = nil } catch { threads = previous; self.error = error.localizedDescription }
    }
    func stop() {
        requestID = nil; request?.cancel(); request = nil; generating = false; calendar.pending = nil
    }
    @discardableResult func send(_ text: String, context: String) -> Bool {
        guard !generating else { return false }
        error = nil
        if let reason = unavailableReason { error = reason; return false }
        if selected == nil { newChat() }
        guard let index = threads.firstIndex(where: { $0.id == selectedID }) else { return false }
        guard threads[index].messages.count < 199 else { error = "This conversation is full. Start a new chat to continue."; return false }
        let previous = threads
        let message = StudyChatMessage(role: "user", text: text.trimmingCharacters(in: .whitespacesAndNewlines), context: context)
        threads[index].messages.append(message)
        if threads[index].messages.count == 1 { threads[index].title = String(message.text.prefix(60)) }
        threads[index].updatedAt = Date()
        do {
            let snapshot = try calendar.snapshot()
            let prompt = try StudyChat.prompt(messages: threads[index].messages, calendarSnapshot: snapshot?.summary)
            try save()
            generate(prompt: prompt, threadID: threads[index].id, snapshot: snapshot)
            return true
        } catch { threads = previous; self.error = error.localizedDescription; return false }
    }
    func retry() {
        guard !generating, let thread = selected, thread.messages.last?.role == "user" else { return }
        if let reason = unavailableReason { error = reason; return }
        do { error = nil; let snapshot = try calendar.snapshot(); generate(prompt: try StudyChat.prompt(messages: thread.messages, calendarSnapshot: snapshot?.summary), threadID: thread.id, snapshot: snapshot) }
        catch { self.error = error.localizedDescription }
    }
    func applyCalendarMove() {
        guard !generating, let proposal = calendar.pending, proposal.threadID == selectedID else { return }
        do {
            let text = try calendar.apply()
            if let index = threads.firstIndex(where: { $0.id == proposal.threadID }), threads[index].messages.count < 200 {
                threads[index].messages.append(StudyChatMessage(role: "assistant", text: text)); threads[index].updatedAt = Date()
                do { try save() } catch { self.error = "The move was applied, but the chat confirmation could not be saved: \(error.localizedDescription)" }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func generate(prompt: String, threadID: UUID, snapshot: CalendarChatSnapshot?) {
        let id = UUID(); requestID = id; generating = true
        request = Task {
            defer { if requestID == id { generating = false; requestID = nil; request = nil } }
            do {
                #if canImport(FoundationModels)
                if #available(macOS 26, *) {
                    let session = LanguageModelSession(instructions: snapshot == nil ? StudyChat.instructions : CalendarChat.instructions)
                    let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.4, maximumResponseTokens: 800))
                    try Task.checkCancellation()
                    guard requestID == id, let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
                    var reply = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !reply.isEmpty, reply.count <= 12_000 else { throw PlanningError.invalid("The model returned an empty or oversized reply. Try a shorter question.") }
                    if let snapshot {
                        let result = try CalendarChatResponse.decode(reply)
                        reply = result.reply
                        if let move = result.move {
                            do { try calendar.propose(move, snapshot: snapshot, threadID: threadID) }
                            catch { reply += "\n\nNo changes made: " + error.localizedDescription }
                        }
                    }
                    threads[index].messages.append(StudyChatMessage(role: "assistant", text: reply)); threads[index].updatedAt = Date()
                    do { try save() } catch { self.error = "The reply is visible but could not be saved: \(error.localizedDescription)" }
                } else { throw PlanningError.invalid(unavailableReason ?? "AI chat is unavailable.") }
                #else
                throw PlanningError.invalid("AI chat is unavailable on this system.")
                #endif
            } catch { if !Task.isCancelled && requestID == id { self.error = "Couldn’t generate a reply: \(error.localizedDescription). Your message is saved; retry or start a new chat." } }
        }
    }
}
