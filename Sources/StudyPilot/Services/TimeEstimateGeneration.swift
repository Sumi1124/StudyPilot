import Foundation
import Observation
import StudyPilotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor enum TimeEstimateGeneration {
    static func estimate(input: EffortEstimateInput, model: ChatModelChoice, client: OllamaClient) async throws -> EffortEstimate {
        if model == .qwen08 { return try await client.estimate(input: input) }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "TimeEstimate", properties: [
                .init(name: "scope", description: "One sentence stating ONLY work still remaining. Student description overrides original task totals. If 4 of 12 are done, estimate 8, not 12. Maximum 500 characters.", schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "minimumMinutes", description: "Plausible lower bound of remaining focused minutes, integer 5 to 100000.", schema: DynamicGenerationSchema(type: Int.self)),
                .init(name: "minutes", description: "Likely remaining focused minutes, at least minimumMinutes and at most 100000.", schema: DynamicGenerationSchema(type: Int.self)),
                .init(name: "maximumMinutes", description: "Plausible upper bound, at least minutes and at most 100000.", schema: DynamicGenerationSchema(type: Int.self)),
                .init(name: "reason", description: "One short sentence explaining effort. No answers or suggested steps. At most 500 characters.", schema: DynamicGenerationSchema(type: String.self))
            ]), dependencies: [])
            let response = try await LanguageModelSession(instructions: EffortEstimation.instructions).respond(to: input.prompt(), schema: schema, options: GenerationOptions(temperature: 0.15, maximumResponseTokens: 600))
            return try EffortEstimate.decode(response.content.jsonString)
        }
        #endif
        throw PlanningError.invalid("Choose an available model in Settings → AI model before estimating.")
    }
}

@MainActor @Observable final class TimeEstimateController {
    private(set) var estimate: EffortEstimate?
    private(set) var basis: EffortEstimateInput?
    private(set) var model: ChatModelChoice?
    private(set) var running = false
    private(set) var error: String?
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    func start(input: EffortEstimateInput, model: ChatModelChoice, client: OllamaClient) {
        cancel(); estimate = nil; basis = input; self.model = model; error = nil
        let id = UUID(); requestID = id; running = true
        request = Task {
            defer { if requestID == id { running = false; request = nil; requestID = nil } }
            do {
                let value = try await TimeEstimateGeneration.estimate(input: input, model: model, client: client)
                try Task.checkCancellation()
                guard requestID == id else { return }
                estimate = value
            } catch { if requestID == id && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func cancel() { requestID = nil; request?.cancel(); request = nil; running = false }
    func invalidate() { cancel(); estimate = nil; basis = nil; error = nil }
}
