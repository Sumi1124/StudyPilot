import Foundation
import Observation
import PDFKit
import StudyPilotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum NotebookSourceImport {
    static func read(_ url: URL) throws -> (title: String, text: String, warning: String?) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100_000_000 else { throw PlanningError.invalid("Choose a file smaller than 100 MB.") }
        let title = url.deletingPathExtension().lastPathComponent
        let text: String
        var warning: String?
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw PlanningError.invalid("This PDF could not be opened. Try downloading a fresh copy of the file.") }
            guard !pdf.isLocked else { throw PlanningError.invalid("Unlock this PDF before importing it.") }
            guard pdf.pageCount <= 500 else { throw PlanningError.invalid("Choose a PDF with up to 500 pages.") }
            var pages = ""
            var unreadablePages = 0
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index) else { continue }
                let extracted = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !extracted.isEmpty else { unreadablePages += 1; continue }
                pages += "[Page \(index + 1)]\n" + extracted + "\n\n"
                guard pages.utf8.count <= NotebookResearch.maximumSourceBytes else { throw PlanningError.invalid("This PDF contains over 1 MB of text. Import a shorter section.") }
            }
            guard !pages.isEmpty else { throw PlanningError.invalid("This PDF has no selectable text. Export it with text recognition (OCR) and try again.") }
            if unreadablePages > 0 { warning = "\(unreadablePages) PDF page\(unreadablePages == 1 ? "" : "s") had no selectable text and were skipped." }
            text = pages
        } else {
            guard ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) else { throw PlanningError.invalid("Import a PDF, Markdown, or plain text file.") }
            text = try String(contentsOf: url, encoding: .utf8)
        }
        try NotebookResearch.validateSource(title: title, text: text)
        return (title, text, warning)
    }
}

@MainActor @Observable final class NotebookResearchController {
    private(set) var answer: NotebookAnswer?
    private(set) var input: NotebookQuestion?
    private(set) var model: ChatModelChoice?
    private(set) var running = false
    private(set) var error: String?
    private var request: Task<Void, Never>?
    private var requestID: UUID?
    func start(input: NotebookQuestion, model: ChatModelChoice, client: OllamaClient) {
        invalidate(); self.input = input; self.model = model; running = true
        let id = UUID(); requestID = id
        request = Task {
            defer { if requestID == id { running = false; request = nil; requestID = nil } }
            do {
                let result = try await Self.generate(input: input, model: model, client: client)
                try Task.checkCancellation()
                guard requestID == id else { return }
                answer = result
            } catch { if requestID == id && !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func cancel() { requestID = nil; request?.cancel(); request = nil; running = false }
    func invalidate() { cancel(); answer = nil; input = nil; error = nil }
    static func generate(input: NotebookQuestion, model: ChatModelChoice, client: OllamaClient) async throws -> NotebookAnswer {
        if model == .qwen08 { return try await client.notebookAnswer(input: input) }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "NotebookAnswer", properties: [
                .init(name: "answer", description: "Answer in under 120 words, based only on excerpts. Empty when insufficient evidence.", schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "passageIDs", description: "One to four supplied excerpt IDs supporting answer, or an empty array if insufficient evidence.", schema: DynamicGenerationSchema(type: [String].self))
            ]), dependencies: [])
            let result = try await LanguageModelSession(instructions: NotebookResearch.instructions).respond(to: input.prompt(), schema: schema, options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 700))
            return try NotebookAnswer.decode(result.content.jsonString, input: input)
        }
        #endif
        throw PlanningError.invalid("Choose an available local model in Settings → AI model.")
    }
}
