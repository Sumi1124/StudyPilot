import Foundation

// Portable, versioned value types shared by the app, backups and tests.

public struct ChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isComplete: Bool
    public init(id: UUID = UUID(), title: String, isComplete: Bool = false) {
        self.id = id; self.title = title; self.isComplete = isComplete
    }
}

public struct SubjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var symbol: String
    public var target: Int
    public init(id: UUID = UUID(), name: String = "", colorHex: String = "6575E8", symbol: String = "book.closed", target: Int = 6) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.target = target
    }
}

public struct ProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var details: String
    public var subjectID: UUID?
    public init(id: UUID = UUID(), title: String = "", details: String = "", subjectID: UUID? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.subjectID = subjectID
    }
}

public struct AssignmentRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var details: String
    public var subjectID: UUID?
    public var projectID: UUID?
    public var dueDate: Date
    public var reminderDate: Date?
    public var priority: Int
    public var status: String
    public var estimatedMinutes: Int
    public var criteria: [String]
    public var checklist: [ChecklistItem]
    public var createdAt: Date
    public var completedAt: Date?
    /// Stored in the existing criteria array to keep older workspaces and JSON backups readable.
    public var ibWorkType: IBWorkType? {
        get { criteria.filter { $0.hasPrefix("ib-type:") }.compactMap { IBWorkType(rawValue: String($0.dropFirst("ib-type:".count))) }.first }
        set {
            criteria.removeAll { $0.hasPrefix("ib-type:") }
            if let newValue { criteria.append("ib-type:\(newValue.rawValue)") }
        }
    }
    public var mypCriteria: [String] { criteria.filter { ["A", "B", "C", "D"].contains($0) } }
    public init(id: UUID = UUID(), title: String = "", details: String = "", subjectID: UUID? = nil, projectID: UUID? = nil, dueDate: Date = Date(), reminderDate: Date? = nil, priority: Int = 1, status: String = "To do", estimatedMinutes: Int = 30, criteria: [String] = [], checklist: [ChecklistItem] = [], createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.subjectID = subjectID
        self.projectID = projectID
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.priority = priority
        self.status = status
        self.estimatedMinutes = estimatedMinutes
        self.criteria = criteria
        self.checklist = checklist
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public enum IBWorkType: String, CaseIterable, Identifiable, Sendable {
    case mypClassTask = "MYP class task"
    case mypAssessment = "MYP assessment"
    case personalProject = "Personal project"
    case dpCoursework = "DP coursework"
    case internalAssessment = "Internal assessment"
    case extendedEssay = "Extended essay"
    case tok = "Theory of knowledge"
    case cas = "CAS"
    case dpExam = "DP exam"
    public var id: String { rawValue }
    public var programme: String { rawValue.hasPrefix("MYP") || self == .personalProject ? "MYP" : "DP" }
    public static func choices(for programme: String) -> [IBWorkType] { allCases.filter { $0.programme == programme } }
}

public struct NotebookRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var subjectID: UUID?
    public init(id: UUID = UUID(), title: String = "", subjectID: UUID? = nil) {
        self.id = id
        self.title = title
        self.subjectID = subjectID
    }
}

public struct NoteRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var notebookID: UUID?
    public var subjectID: UUID?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String = "Untitled note", body: String = "", notebookID: UUID? = nil, subjectID: UUID? = nil, tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.notebookID = notebookID
        self.subjectID = subjectID
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DeckRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var subjectID: UUID?
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public init(id: UUID = UUID(), title: String = "", subjectID: UUID? = nil, reminderEnabled: Bool = false, reminderHour: Int = 18) {
        self.id = id
        self.title = title
        self.subjectID = subjectID
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
    }
}

public struct FlashcardRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var deckID: UUID
    public var question: String
    public var answer: String
    public var dueDate: Date
    public var intervalDays: Int
    public var ease: Double
    public var repetitions: Int
    public var lapses: Int
    public var createdAt: Date
    public init(id: UUID = UUID(), deckID: UUID = UUID(), question: String = "", answer: String = "", dueDate: Date = Date(), intervalDays: Int = 0, ease: Double = 2.5, repetitions: Int = 0, lapses: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.deckID = deckID
        self.question = question
        self.answer = answer
        self.dueDate = dueDate
        self.intervalDays = intervalDays
        self.ease = ease
        self.repetitions = repetitions
        self.lapses = lapses
        self.createdAt = createdAt
    }
}

public struct ReviewRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var cardID: UUID
    public var deckID: UUID
    public var reviewedAt: Date
    public var rating: String
    public var intervalDays: Int
    public init(id: UUID = UUID(), cardID: UUID = UUID(), deckID: UUID = UUID(), reviewedAt: Date = Date(), rating: String = "Good", intervalDays: Int = 1) {
        self.id = id
        self.cardID = cardID
        self.deckID = deckID
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.intervalDays = intervalDays
    }
}

public struct StudySessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var subjectID: UUID?
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: Double
    public var plannedSeconds: Double
    public var completed: Bool
    public init(id: UUID = UUID(), subjectID: UUID? = nil, startedAt: Date = Date(), endedAt: Date = Date(), durationSeconds: Double = 0, plannedSeconds: Double = 1500, completed: Bool = false) {
        self.id = id
        self.subjectID = subjectID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.plannedSeconds = plannedSeconds
        self.completed = completed
    }
}

public struct AssessmentRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var subjectID: UUID
    public var title: String
    public var date: Date
    public var criterionA: Int?
    public var criterionB: Int?
    public var criterionC: Int?
    public var criterionD: Int?
    public var reflection: String
    public init(id: UUID = UUID(), subjectID: UUID = UUID(), title: String = "", date: Date = Date(), criterionA: Int? = nil, criterionB: Int? = nil, criterionC: Int? = nil, criterionD: Int? = nil, reflection: String = "") {
        self.id = id
        self.subjectID = subjectID
        self.title = title
        self.date = date
        self.criterionA = criterionA
        self.criterionB = criterionB
        self.criterionC = criterionC
        self.criterionD = criterionD
        self.reflection = reflection
    }
}

public struct PlannerEventRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var subjectID: UUID?
    public var kind: String
    public var startDate: Date
    public var durationMinutes: Int
    public var reminderDate: Date?
    public var details: String
    public init(id: UUID = UUID(), title: String = "", subjectID: UUID? = nil, kind: String = "Study", startDate: Date = Date(), durationMinutes: Int = 60, reminderDate: Date? = nil, details: String = "") {
        self.id = id
        self.title = title
        self.subjectID = subjectID
        self.kind = kind
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.reminderDate = reminderDate
        self.details = details
    }
}
