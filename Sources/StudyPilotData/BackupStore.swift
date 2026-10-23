import Foundation
import SwiftData
import StudyPilotCore

@MainActor public enum BackupStore {
    public static func snapshot(_ context: ModelContext) throws -> BackupEnvelope {
        try context.save()
        return try BackupEnvelope(
            subjects: context.fetch(FetchDescriptor<Subject>()).map(\.record),
            projects: context.fetch(FetchDescriptor<Project>()).map(\.record),
            assignments: context.fetch(FetchDescriptor<Assignment>()).map(\.record),
            notebooks: context.fetch(FetchDescriptor<Notebook>()).map(\.record),
            notes: context.fetch(FetchDescriptor<Note>()).map(\.record),
            decks: context.fetch(FetchDescriptor<Deck>()).map(\.record),
            cards: context.fetch(FetchDescriptor<Flashcard>()).map(\.record),
            reviews: context.fetch(FetchDescriptor<Review>()).map(\.record),
            sessions: context.fetch(FetchDescriptor<StudySession>()).map(\.record),
            assessments: context.fetch(FetchDescriptor<Assessment>()).map(\.record),
            events: context.fetch(FetchDescriptor<PlannerEvent>()).map(\.record)
        )
    }
    /// Reconciles by stable ID in one save, avoiding delete/reinsert uniqueness conflicts.
    public static func restore(_ backup: BackupEnvelope, into context: ModelContext) throws {
        try BackupCodec.validate(backup)
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            let subjectsExisting = try context.fetch(FetchDescriptor<Subject>())
            let subjectsIDs = Set(backup.subjects.map(\.id))
            let subjectsMap = Dictionary(uniqueKeysWithValues: subjectsExisting.map { ($0.id, $0) })
            for item in subjectsExisting where !subjectsIDs.contains(item.id) { context.delete(item) }
            for record in backup.subjects {
                if let item = subjectsMap[record.id] { item.apply(record) } else { context.insert(Subject(record)) }
            }
            let projectsExisting = try context.fetch(FetchDescriptor<Project>())
            let projectsIDs = Set(backup.projects.map(\.id))
            let projectsMap = Dictionary(uniqueKeysWithValues: projectsExisting.map { ($0.id, $0) })
            for item in projectsExisting where !projectsIDs.contains(item.id) { context.delete(item) }
            for record in backup.projects {
                if let item = projectsMap[record.id] { item.apply(record) } else { context.insert(Project(record)) }
            }
            let assignmentsExisting = try context.fetch(FetchDescriptor<Assignment>())
            let assignmentsIDs = Set(backup.assignments.map(\.id))
            let assignmentsMap = Dictionary(uniqueKeysWithValues: assignmentsExisting.map { ($0.id, $0) })
            for item in assignmentsExisting where !assignmentsIDs.contains(item.id) { context.delete(item) }
            for record in backup.assignments {
                if let item = assignmentsMap[record.id] { item.apply(record) } else { context.insert(Assignment(record)) }
            }
            let notebooksExisting = try context.fetch(FetchDescriptor<Notebook>())
            let notebooksIDs = Set(backup.notebooks.map(\.id))
            let notebooksMap = Dictionary(uniqueKeysWithValues: notebooksExisting.map { ($0.id, $0) })
            for item in notebooksExisting where !notebooksIDs.contains(item.id) { context.delete(item) }
            for record in backup.notebooks {
                if let item = notebooksMap[record.id] { item.apply(record) } else { context.insert(Notebook(record)) }
            }
            let notesExisting = try context.fetch(FetchDescriptor<Note>())
            let notesIDs = Set(backup.notes.map(\.id))
            let notesMap = Dictionary(uniqueKeysWithValues: notesExisting.map { ($0.id, $0) })
            for item in notesExisting where !notesIDs.contains(item.id) { context.delete(item) }
            for record in backup.notes {
                if let item = notesMap[record.id] { item.apply(record) } else { context.insert(Note(record)) }
            }
            let decksExisting = try context.fetch(FetchDescriptor<Deck>())
            let decksIDs = Set(backup.decks.map(\.id))
            let decksMap = Dictionary(uniqueKeysWithValues: decksExisting.map { ($0.id, $0) })
            for item in decksExisting where !decksIDs.contains(item.id) { context.delete(item) }
            for record in backup.decks {
                if let item = decksMap[record.id] { item.apply(record) } else { context.insert(Deck(record)) }
            }
            let cardsExisting = try context.fetch(FetchDescriptor<Flashcard>())
            let cardsIDs = Set(backup.cards.map(\.id))
            let cardsMap = Dictionary(uniqueKeysWithValues: cardsExisting.map { ($0.id, $0) })
            for item in cardsExisting where !cardsIDs.contains(item.id) { context.delete(item) }
            for record in backup.cards {
                if let item = cardsMap[record.id] { item.apply(record) } else { context.insert(Flashcard(record)) }
            }
            let reviewsExisting = try context.fetch(FetchDescriptor<Review>())
            let reviewsIDs = Set(backup.reviews.map(\.id))
            let reviewsMap = Dictionary(uniqueKeysWithValues: reviewsExisting.map { ($0.id, $0) })
            for item in reviewsExisting where !reviewsIDs.contains(item.id) { context.delete(item) }
            for record in backup.reviews {
                if let item = reviewsMap[record.id] { item.apply(record) } else { context.insert(Review(record)) }
            }
            let sessionsExisting = try context.fetch(FetchDescriptor<StudySession>())
            let sessionsIDs = Set(backup.sessions.map(\.id))
            let sessionsMap = Dictionary(uniqueKeysWithValues: sessionsExisting.map { ($0.id, $0) })
            for item in sessionsExisting where !sessionsIDs.contains(item.id) { context.delete(item) }
            for record in backup.sessions {
                if let item = sessionsMap[record.id] { item.apply(record) } else { context.insert(StudySession(record)) }
            }
            let assessmentsExisting = try context.fetch(FetchDescriptor<Assessment>())
            let assessmentsIDs = Set(backup.assessments.map(\.id))
            let assessmentsMap = Dictionary(uniqueKeysWithValues: assessmentsExisting.map { ($0.id, $0) })
            for item in assessmentsExisting where !assessmentsIDs.contains(item.id) { context.delete(item) }
            for record in backup.assessments {
                if let item = assessmentsMap[record.id] { item.apply(record) } else { context.insert(Assessment(record)) }
            }
            let eventsExisting = try context.fetch(FetchDescriptor<PlannerEvent>())
            let eventsIDs = Set(backup.events.map(\.id))
            let eventsMap = Dictionary(uniqueKeysWithValues: eventsExisting.map { ($0.id, $0) })
            for item in eventsExisting where !eventsIDs.contains(item.id) { context.delete(item) }
            for record in backup.events {
                if let item = eventsMap[record.id] { item.apply(record) } else { context.insert(PlannerEvent(record)) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}