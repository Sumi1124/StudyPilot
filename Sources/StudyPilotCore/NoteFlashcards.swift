import Foundation

public struct NoteFlashcardDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var question: String
    public var answer: String
    public init(question: String = "", answer: String = "") { id = UUID(); self.question = question; self.answer = answer }
    public var isValid: Bool { !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var key: [String] { [question, answer].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } }
}
public enum NoteFlashcards {
    public static func parse(_ text: String) -> [NoteFlashcardDraft] {
        var seen = Set<[String]>()
        return text.components(separatedBy: .newlines).compactMap { line in
            guard let separator = line.range(of: "::") else { return nil }
            let card = NoteFlashcardDraft(question: String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), answer: String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            guard card.isValid, seen.insert(card.key).inserted else { return nil }
            return card
        }
    }
}
