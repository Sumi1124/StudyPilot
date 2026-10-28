import Testing
import Foundation
import SwiftData
import StudyPilotCore
@testable import StudyPilotData

@Test @MainActor func notebookSourceCopiesAndCitedNotesSurvivePortableBackup() throws {
    let container = try DataStore.makeContainer(inMemory: true), context = container.mainContext
    let notebook = NotebookRecord(title: "Source notebook")
    let original = NoteRecord(title: "Class notes", body: "Original class material")
    let source = NoteRecord(title: original.title, body: original.body, notebookID: notebook.id, tags: [NotebookResearch.sourceTag])
    let answer = NoteRecord(title: "Saved question", body: "Explanation\n\nOriginal class material", notebookID: notebook.id, tags: [NotebookResearch.answerTag])
    context.insert(Notebook(notebook)); for record in [original, source, answer] { context.insert(Note(record)) }; try context.save()
    let portable = try BackupCodec.decode(BackupCodec.encode(BackupStore.snapshot(context)))
    let restored = try DataStore.makeContainer(inMemory: true)
    try BackupStore.restore(portable, into: restored.mainContext)
    let notes = try restored.mainContext.fetch(FetchDescriptor<Note>())
    #expect(notes.first { $0.id == source.id }?.record == source)
    #expect(notes.first { $0.id == answer.id }?.record == answer)
    let originalCopy = try #require(notes.first { $0.id == original.id }); originalCopy.body = "Newer original material"
    try restored.mainContext.save()
    #expect(notes.first { $0.id == source.id }?.body == "Original class material")
    let importedCopy = try #require(notes.first { $0.id == source.id }); restored.mainContext.delete(importedCopy); try restored.mainContext.save()
    #expect(try restored.mainContext.fetchCount(FetchDescriptor<Note>()) == 2)
    #expect(try restored.mainContext.fetchCount(FetchDescriptor<Notebook>()) == 1)
}

@Test @MainActor func plannedWorkSurvivesBackupAndIsNotScheduledTwice() throws {
    let container = try DataStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15))!
    let task = PlanningTask(id: "calendar:science:deadline-1", title: "Science investigation", deadline: now.addingTimeInterval(86_400), minutes: 60, steps: ["Review the evidence", "Draft the reflection"])
    let plan = try StudyPlanner.makePlan(tasks: [task], busy: [], preferences: PlanningPreferences(), now: now, calendar: calendar)
    for block in plan.blocks {
        context.insert(PlannerEvent(PlannerEventRecord(id: block.id, title: block.title, startDate: block.start, durationMinutes: block.minutes, details: block.notes)))
    }
    try context.save()
    let portable = try BackupCodec.decode(BackupCodec.encode(BackupStore.snapshot(context)))
    let restored = try DataStore.makeContainer(inMemory: true)
    try BackupStore.restore(portable, into: restored.mainContext)
    let events = try restored.mainContext.fetch(FetchDescriptor<PlannerEvent>())
    #expect(events.count == plan.blocks.count)
    let busy = events.map { PlanningBusyTime(start: $0.startDate, end: $0.startDate.addingTimeInterval(Double($0.durationMinutes * 60)), taskID: PlannedStudyBlock.taskID(in: $0.details)) }
    let secondPlan = try StudyPlanner.makePlan(tasks: [task], busy: busy, preferences: PlanningPreferences(), now: now, calendar: calendar)
    #expect(secondPlan.blocks.isEmpty)
    #expect(secondPlan.alreadyPlannedMinutes == 60)
    #expect(secondPlan.unscheduled.isEmpty)
}

@Test @MainActor func assignmentsAndNotesPersistAcrossContainerReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let id = UUID()
    do {
        let container = try DataStore.makeContainer(at: url)
        let context = ModelContext(container)
        context.insert(Assignment(AssignmentRecord(id: id, title: "Investigate", checklist: [ChecklistItem(title: "Plan", isComplete: true)])))
        context.insert(Note(NoteRecord(title: "Research", body: "# My notes\nOffline and persistent", tags: ["science"])))
        try context.save()
    }
    let reopened = try DataStore.makeContainer(at: url)
    let context = ModelContext(reopened)
    let tasks = try context.fetch(FetchDescriptor<Assignment>())
    #expect(tasks.count == 1)
    #expect(tasks.first?.id == id)
    #expect(tasks.first?.checklist.first?.isComplete == true)
    let notes = try context.fetch(FetchDescriptor<Note>())
    #expect(notes.first?.tags == ["science"])
    #expect(notes.first?.body.contains("persistent") == true)
}

@Test @MainActor func restoreReconcilesIDsAndRejectsInvalidDataBeforeMutation() throws {
    let container = try DataStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let subject = Subject(SubjectRecord(name: "Mathematics"))
    let note = Note(NoteRecord(title: "Original", subjectID: subject.id))
    context.insert(subject); context.insert(note); try context.save()
    var backup = try BackupStore.snapshot(context)
    backup.notes[0].title = "Restored title"
    backup.notes.append(NoteRecord(title: "New note", subjectID: subject.id))
    try BackupStore.restore(backup, into: context)
    #expect(try context.fetchCount(FetchDescriptor<Note>()) == 2)
    #expect(note.title == "Restored title")
    let before = try BackupStore.snapshot(context)
    var bad = before; bad.subjects[0].target = 99
    #expect(throws: BackupError.self) { try BackupStore.restore(bad, into: context) }
    #expect(try context.fetchCount(FetchDescriptor<Note>()) == 2)
    #expect(subject.target == 6)
    var replacement = before; replacement.notes = []
    try BackupStore.restore(replacement, into: context)
    #expect(try context.fetchCount(FetchDescriptor<Note>()) == 0)
}
@Test @MainActor func subjectPresetsAreIdempotent() throws {
    let container = try DataStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    try DataStore.seedSubjectsIfNeeded(context)
    try DataStore.seedSubjectsIfNeeded(context)
    #expect(try context.fetchCount(FetchDescriptor<Subject>()) == 5)
}
@Test @MainActor func reviewAndSchedulePersistTogether() throws {
    let container = try DataStore.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let deck = Deck(DeckRecord(title: "Science")); let card = Flashcard(FlashcardRecord(deckID: deck.id, question: "Q", answer: "A"))
    context.insert(deck); context.insert(card); try context.save()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    card.apply(ReviewScheduler.schedule(card.record, rating: .good, now: now))
    context.insert(Review(ReviewRecord(cardID: card.id, deckID: deck.id, reviewedAt: now)))
    try context.save()
    let another = ModelContext(container)
    #expect(try another.fetch(FetchDescriptor<Flashcard>()).first?.intervalDays == 1)
    #expect(try another.fetchCount(FetchDescriptor<Review>()) == 1)
}

@Test @MainActor func allElevenRecordTypesSurviveDiskRestoration() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("full.store")
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let subject = SubjectRecord(name: "Sciences", target: 7)
    let project = ProjectRecord(title: "Investigation", subjectID: subject.id)
    let notebook = NotebookRecord(title: "Notes", subjectID: subject.id)
    let deck = DeckRecord(title: "Recall", subjectID: subject.id, reminderEnabled: true, reminderHour: 16)
    let card = FlashcardRecord(deckID: deck.id, question: "Question", answer: "Answer", dueDate: date, intervalDays: 3, ease: 2.2, repetitions: 2, lapses: 1, createdAt: date)
    let original = BackupEnvelope(exportedAt: date, subjects: [subject], projects: [project], assignments: [AssignmentRecord(title: "Report", subjectID: subject.id, projectID: project.id, dueDate: date, reminderDate: date.addingTimeInterval(-3600), priority: 2, status: "In progress", criteria: ["A", "C"], checklist: [ChecklistItem(title: "Plan", isComplete: true)], createdAt: date)], notebooks: [notebook], notes: [NoteRecord(title: "Research", body: "日本語 · x²", notebookID: notebook.id, subjectID: subject.id, tags: ["science"], createdAt: date, updatedAt: date)], decks: [deck], cards: [card], reviews: [ReviewRecord(cardID: card.id, deckID: deck.id, reviewedAt: date, rating: "Good", intervalDays: 3)], sessions: [StudySessionRecord(subjectID: subject.id, startedAt: date, endedAt: date.addingTimeInterval(500), durationSeconds: 480)], assessments: [AssessmentRecord(subjectID: subject.id, title: "Test", date: date, criterionA: 0, criterionB: 8, reflection: "Keep practising")], events: [PlannerEventRecord(title: "Exam", subjectID: subject.id, kind: "Exam", startDate: date, durationMinutes: 90)])
    do {
        let container = try DataStore.makeContainer(at: url)
        try BackupStore.restore(original, into: ModelContext(container))
    }
    let reopened = try DataStore.makeContainer(at: url)
    var restored = try BackupStore.snapshot(ModelContext(reopened))
    restored.exportedAt = original.exportedAt
    #expect(restored == original)
}
