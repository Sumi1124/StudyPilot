import Foundation

public struct BackupEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var subjects: [SubjectRecord]
    public var projects: [ProjectRecord]
    public var assignments: [AssignmentRecord]
    public var notebooks: [NotebookRecord]
    public var notes: [NoteRecord]
    public var decks: [DeckRecord]
    public var cards: [FlashcardRecord]
    public var reviews: [ReviewRecord]
    public var sessions: [StudySessionRecord]
    public var assessments: [AssessmentRecord]
    public var events: [PlannerEventRecord]
    public init(version: Int = 1, exportedAt: Date = Date(), subjects: [SubjectRecord] = [], projects: [ProjectRecord] = [], assignments: [AssignmentRecord] = [], notebooks: [NotebookRecord] = [], notes: [NoteRecord] = [], decks: [DeckRecord] = [], cards: [FlashcardRecord] = [], reviews: [ReviewRecord] = [], sessions: [StudySessionRecord] = [], assessments: [AssessmentRecord] = [], events: [PlannerEventRecord] = []) {
        self.version = version
        self.exportedAt = exportedAt
        self.subjects = subjects
        self.projects = projects
        self.assignments = assignments
        self.notebooks = notebooks
        self.notes = notes
        self.decks = decks
        self.cards = cards
        self.reviews = reviews
        self.sessions = sessions
        self.assessments = assessments
        self.events = events
    }
    public var recordCount: Int { subjects.count + projects.count + assignments.count + notebooks.count + notes.count + decks.count + cards.count + reviews.count + sessions.count + assessments.count + events.count }
}

public enum BackupError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
public enum BackupCodec {
    public static let maximumBytes = 50 * 1024 * 1024
    public static func encode(_ backup: BackupEnvelope) throws -> Data {
        try validate(backup)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        guard data.count <= maximumBytes else { throw BackupError.invalid("This workspace exceeds the 50 MB portable backup limit.") }
        return data
    }
    public static func decode(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= maximumBytes else { throw BackupError.invalid("This file exceeds the 50 MB import limit.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(BackupEnvelope.self, from: data)
        try validate(value); return value
    }
    public static func validate(_ value: BackupEnvelope) throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw BackupError.invalid(message) } }
        func unique<T: Identifiable>(_ records: [T], _ name: String) throws where T.ID: Hashable { try require(Set(records.map(\.id)).count == records.count, "Duplicate identifiers in \(name).") }
        func title(_ text: String) throws { try require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 10_000, "Titles must contain 1–10,000 characters.") }
        func text(_ text: String) throws { try require(text.utf8.count <= 5_000_000, "A text field exceeds the 5 MB limit.") }
        func date(_ date: Date) throws { try require(date.timeIntervalSince1970.isFinite && (-2_208_988_800...10_413_792_000).contains(date.timeIntervalSince1970), "A date is outside the supported 1900–2300 range.") }
        try date(value.exportedAt)
        try require(value.version == 1, "Unsupported backup version \(value.version). This app supports version 1.")
        try require(value.recordCount <= 100_000, "This backup exceeds 100,000 records.")
        try unique(value.subjects, "subjects"); try unique(value.projects, "projects"); try unique(value.assignments, "assignments")
        try unique(value.notebooks, "notebooks"); try unique(value.notes, "notes"); try unique(value.decks, "decks")
        try unique(value.cards, "cards"); try unique(value.reviews, "reviews"); try unique(value.sessions, "sessions")
        try unique(value.assessments, "assessments"); try unique(value.events, "events")
        let subjectIDs = Set(value.subjects.map(\.id)); let projectIDs = Set(value.projects.map(\.id)); let notebookIDs = Set(value.notebooks.map(\.id)); let deckIDs = Set(value.decks.map(\.id))
        let cardMap = Dictionary(uniqueKeysWithValues: value.cards.map { ($0.id, $0) })
        func subject(_ id: UUID?) throws { if let id { try require(subjectIDs.contains(id), "A record refers to a missing subject.") } }
        for item in value.subjects {
            try title(item.name); try require((0...8).contains(item.target), "Criterion targets must be 0–8.")
            try require(item.colorHex.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil, "A subject color is invalid.")
            try require(item.symbol.count < 128, "A subject icon name is too long.")
        }
        for item in value.projects { try title(item.title); try text(item.details); try subject(item.subjectID) }
        for item in value.notebooks { try title(item.title); try subject(item.subjectID) }
        for item in value.assignments {
            try title(item.title); try text(item.details); try subject(item.subjectID); try date(item.dueDate); try date(item.createdAt)
            if let id = item.projectID { try require(projectIDs.contains(id), "An assignment refers to a missing project.") }
            if let reminder = item.reminderDate { try date(reminder); try require(reminder < item.dueDate, "An assignment reminder must precede its deadline.") }
            if let completed = item.completedAt { try date(completed) }
            try require(TaskStatus(rawValue: item.status) != nil && (0...2).contains(item.priority), "An assignment status or priority is invalid.")
            try require((5...1440).contains(item.estimatedMinutes), "Assignment estimates must be 5–1,440 minutes.")
            try require(Set(item.criteria).isSubset(of: Set(Criterion.allCases.map(\.rawValue))) && Set(item.criteria).count == item.criteria.count, "Assessment criteria must be unique values A, B, C, or D.")
            try unique(item.checklist, "subtasks"); try require(item.checklist.count <= 1000, "An assignment has too many subtasks.")
            for step in item.checklist { try title(step.title) }
        }
        for item in value.notes {
            try title(item.title); try text(item.body); try subject(item.subjectID); try date(item.createdAt); try date(item.updatedAt)
            if let id = item.notebookID { try require(notebookIDs.contains(id), "A note refers to a missing notebook.") }
            try require(item.tags.count <= 1000 && item.tags.allSatisfy { $0.count <= 200 }, "Note tags exceed the supported limit.")
        }
        for item in value.decks { try title(item.title); try subject(item.subjectID); try require((0...23).contains(item.reminderHour), "A revision reminder hour is invalid.") }
        for item in value.cards {
            try title(item.question); try title(item.answer); try date(item.dueDate); try date(item.createdAt)
            try require(deckIDs.contains(item.deckID), "A flashcard refers to a missing deck.")
            try require(item.ease.isFinite && (1.3...3).contains(item.ease) && (0...36_500).contains(item.intervalDays) && (0...1_000_000).contains(item.repetitions) && (0...1_000_000).contains(item.lapses), "A flashcard schedule is invalid.")
        }
        for item in value.reviews {
            try date(item.reviewedAt)
            try require(cardMap[item.cardID]?.deckID == item.deckID && deckIDs.contains(item.deckID), "Review history refers to a missing card or the wrong deck.")
            try require(ReviewRating(rawValue: item.rating) != nil && (0...36_500).contains(item.intervalDays), "A review rating or interval is invalid.")
        }
        for item in value.sessions {
            try subject(item.subjectID); try date(item.startedAt); try date(item.endedAt)
            try require(item.durationSeconds.isFinite && item.plannedSeconds.isFinite && item.durationSeconds >= 0 && item.durationSeconds <= item.plannedSeconds && (60...14_400).contains(item.plannedSeconds) && item.startedAt <= item.endedAt, "A study session duration or date is invalid.")
        }
        for item in value.assessments {
            try title(item.title); try subject(item.subjectID); try date(item.date); try text(item.reflection)
            let scores = [item.criterionA, item.criterionB, item.criterionC, item.criterionD].compactMap { $0 }
            try require(!scores.isEmpty && scores.allSatisfy { (0...8).contains($0) }, "Assessments need at least one criterion score on the 0–8 scale.")
        }
        for item in value.events {
            try title(item.title); try text(item.details); try subject(item.subjectID); try date(item.startDate)
            try require(["Study", "Exam"].contains(item.kind) && (5...720).contains(item.durationMinutes), "An event type or duration is invalid.")
            if let reminder = item.reminderDate { try date(reminder); try require(reminder < item.startDate, "An event reminder must precede the event.") }
        }
    }
}
