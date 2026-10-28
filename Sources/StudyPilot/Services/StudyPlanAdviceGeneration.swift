import Foundation
import Observation
import StudyPilotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor enum StudyPlanAdviceGeneration {
    static func suggest(input: StudyPlanAdviceInput, model: ChatModelChoice, client: OllamaClient) async throws -> StudyPlanAdvice {
        if model == .qwen08 { return try await client.studyPlanAdvice(input: input) }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "StudyPlanAdvice", properties: [
                .init(name: "sessionMinutes", description: "Exactly 25, 50, or 60 focused minutes per session.", schema: DynamicGenerationSchema(type: Int.self)),
                .init(name: "dailyMinutes", description: "A sustainable daily study limit from 30 through 480, as a multiple of 30.", schema: DynamicGenerationSchema(type: Int.self)),
                .init(name: "planAheadDays", description: "Exactly 7, 14, or 28 calendar days.", schema: DynamicGenerationSchema(type: Int.self)),
                .init(name: "summary", description: "One concise sentence describing workload pressure. No assignment answers or steps. Maximum 500 characters.", schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "rationale", description: "One concise sentence explaining the recommended schedule settings. No assignment answers or steps. Maximum 700 characters.", schema: DynamicGenerationSchema(type: String.self))
            ]), dependencies: [])
            let response = try await LanguageModelSession(instructions: StudyPlanAdvising.instructions)
                .respond(to: input.prompt(), schema: schema, options: GenerationOptions(temperature: 0.15, maximumResponseTokens: 600))
            return try StudyPlanAdvice.decode(response.content.jsonString)
        }
        #endif
        throw PlanningError.invalid("Choose an available model in Settings → AI model before asking for planning help.")
    }
}

@MainActor @Observable final class StudyPlanAdviceController {
    private(set) var advice: StudyPlanAdvice?
    private(set) var basis: StudyPlanAdviceInput?
    private(set) var model: ChatModelChoice?
    private(set) var running = false
    private(set) var error: String?
    private var request: Task<Void, Never>?
    private var requestID: UUID?

    func start(input: StudyPlanAdviceInput, model: ChatModelChoice, client: OllamaClient) {
        cancel()
        advice = nil
        basis = input
        self.model = model
        error = nil
        let id = UUID()
        requestID = id
        running = true
        request = Task {
            defer {
                if requestID == id {
                    running = false
                    request = nil
                    requestID = nil
                }
            }
            do {
                let value = try await StudyPlanAdviceGeneration.suggest(input: input, model: model, client: client)
                try Task.checkCancellation()
                guard requestID == id else { return }
                advice = value
            } catch {
                if requestID == id && !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func cancel() {
        requestID = nil
        request?.cancel()
        request = nil
        running = false
    }

    func invalidate() {
        cancel()
        advice = nil
        basis = nil
        error = nil
    }
}
