import Foundation
import SwiftData
import StudyPilotCore

@MainActor public enum DataStore {
    public static var schema: Schema {
        Schema([Subject.self, Project.self, Assignment.self, Notebook.self, Note.self, Deck.self, Flashcard.self, Review.self, StudySession.self, Assessment.self, PlannerEvent.self])
    }
    public static func makeContainer(at url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    public static func seedSubjectsIfNeeded(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Subject>()) == 0 else { return }
        let defaults = [
            ("Mathematics", "6877E8", "function"),
            ("Sciences", "2B998C", "atom"),
            ("English", "CF8955", "text.book.closed"),
            ("Individuals & Societies", "A178C5", "globe.europe.africa"),
            ("Design", "D06785", "pencil.and.ruler")
        ]
        for (name, color, symbol) in defaults { context.insert(Subject(SubjectRecord(name: name, colorHex: color, symbol: symbol))) }
        try context.save()
    }
}
