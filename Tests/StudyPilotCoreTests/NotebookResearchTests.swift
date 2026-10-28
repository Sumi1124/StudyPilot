import Foundation
import Testing
@testable import StudyPilotCore

@Test func notebookRetrievalUsesOnlySelectedMaterialAndStablePassages() throws {
    let note = NoteRecord(title: "Algebra", body: String(repeating: "Practice ", count: 150) + "A quadratic equation has a squared variable.")
    let passages = NotebookResearch.passages(in: note)
    #expect(passages.count > 1)
    #expect(passages.map(\.text).joined() == note.body)
    #expect(passages.allSatisfy { $0.text.utf8.count <= 900 })
    #expect(passages == NotebookResearch.passages(in: note))
    let match = try #require(NotebookResearch.relevant(question: "What is a quadratic equation?", passages: passages).first)
    #expect(match.text.contains("squared variable"))
    #expect(NotebookResearch.relevant(question: "photosynthesis", passages: passages).isEmpty)
    #expect(NotebookResearch.context(question: "quadratic", sources: []).isEmpty)
    #expect(NotebookResearch.relevant(question: "quadratic", passages: passages, limit: -1).isEmpty)
}

@Test func notebookMultilingualContextStaysBoundedAndSamplesDifferentSources() throws {
    let japanese = NoteRecord(title: "理科", body: String(repeating: "光合成は植物の働きです。", count: 1000))
    let chunks = NotebookResearch.passages(in: japanese)
    #expect(chunks.allSatisfy { $0.text.utf8.count <= 900 && !$0.text.contains("�") })
    #expect(chunks.map(\.text).joined() == japanese.body)
    #expect(!NotebookResearch.relevant(question: "光合成について教えて", passages: chunks).isEmpty)
    let second = NoteRecord(title: "Other", body: "Unrelated class notes")
    let input = try NotebookQuestion(question: "Compare the readings", passages: NotebookResearch.context(question: "Compare the readings", sources: [japanese, second]))
    #expect(input.passages.count <= 8)
    #expect(input.passages.contains { $0.sourceID == second.id })
    #expect(try input.prompt().utf8.count < 12_000)
}

@Test func notebookAnswersRejectInventedCitationsAndNormalizeMissingEvidence() throws {
    let input = try NotebookQuestion(question: "What is algebra?", passages: NotebookResearch.passages(in: NoteRecord(title: "Algebra", body: "Algebra uses variables.")))
    let answer = try NotebookAnswer.decode(#"{"answer":"It uses variables.","passageIDs":["S1"]}"#, input: input)
    #expect(answer.citations == input.passages)
    #expect(answer.citations.first?.text == "Algebra uses variables.")
    #expect(throws: (any Error).self) { try NotebookAnswer.decode(#"{"answer":"Invented","passageIDs":["S999"]}"#, input: input) }
    #expect(throws: (any Error).self) { try NotebookAnswer.decode(#"{"answer":"Duplicate","passageIDs":["S1","S1"]}"#, input: input) }
    #expect(throws: (any Error).self) { try NotebookAnswer.decode(#"{"answer":"","passageIDs":["S1"]}"#, input: input) }
    let insufficient = try NotebookAnswer.decode(#"{"answer":"An unsupported claim","passageIDs":[]}"#, input: input)
    #expect(!insufficient.text.contains("unsupported claim"))
    #expect(insufficient.citations.isEmpty)
}

@Test func notebookImportAndQuestionBoundariesRejectInvalidInput() throws {
    #expect(throws: (any Error).self) { try NotebookResearch.validateSource(title: "Source", text: " \n ") }
    #expect(throws: (any Error).self) { try NotebookResearch.validateSource(title: " ", text: "Text") }
    #expect(throws: (any Error).self) { try NotebookResearch.validateSource(title: "Source", text: String(repeating: "a", count: 200_001)) }
    try NotebookResearch.validateSource(title: "Source", text: String(repeating: "a", count: 200_000))
    #expect(throws: (any Error).self) { try NotebookQuestion(question: "Question", passages: []) }
    let passages = NotebookResearch.passages(in: NoteRecord(body: "Some source text"))
    #expect(throws: (any Error).self) { try NotebookQuestion(question: "   ", passages: passages) }
    #expect(throws: (any Error).self) { try NotebookQuestion(question: String(repeating: "?", count: 601), passages: passages) }
    #expect(throws: (any Error).self) { try NotebookQuestion(question: "Question", passages: passages + passages) }
}

@Test func notebookLocalRequestHasNoActionOrDownloadAndUsesExactModel() throws {
    let input = try NotebookQuestion(question: "Explain variables", passages: NotebookResearch.passages(in: NoteRecord(body: "A variable represents a value.")))
    let body = try #require(JSONSerialization.jsonObject(with: NotebookResearch.ollamaBody(input: input)) as? [String: Any])
    #expect(body["model"] as? String == OllamaWire.model)
    #expect(body["stream"] as? Bool == false)
    let schema = try #require(body["format"] as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    #expect(Set(properties.keys) == ["answer", "passageIDs"])
    #expect(try input.prompt().contains("\"id\":\"S1\""))
    #expect(NotebookResearch.instructions.contains("untrusted reference data"))
    #expect(NotebookResearch.instructions.contains("do not contain enough evidence"))
}
