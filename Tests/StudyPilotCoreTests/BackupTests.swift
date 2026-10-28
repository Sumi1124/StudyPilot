import Testing
import Foundation
@testable import StudyPilotCore

func sampleBackup() -> BackupEnvelope {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let subject = SubjectRecord(name: "Science")
    let project = ProjectRecord(title: "Investigation", subjectID: subject.id)
    let notebook = NotebookRecord(title: "Class notes", subjectID: subject.id)
    let deck = DeckRecord(title: "Revision", subjectID: subject.id)
    let card = FlashcardRecord(deckID: deck.id, question: "What is energy?", answer: "Capacity to do work", dueDate: date, createdAt: date)
    return BackupEnvelope(exportedAt: date, subjects: [subject], projects: [project], assignments: [AssignmentRecord(title: "Lab report", subjectID: subject.id, projectID: project.id, dueDate: date, criteria: ["A", "B"], checklist: [ChecklistItem(title: "Write")], createdAt: date)], notebooks: [notebook], notes: [NoteRecord(title: "Forces", body: "# Newton\nF = ma", notebookID: notebook.id, subjectID: subject.id, tags: ["physics"], createdAt: date, updatedAt: date)], decks: [deck], cards: [card], reviews: [ReviewRecord(cardID: card.id, deckID: deck.id, reviewedAt: date)], sessions: [StudySessionRecord(subjectID: subject.id, startedAt: date, endedAt: date.addingTimeInterval(1500), durationSeconds: 1500, completed: true)], assessments: [AssessmentRecord(subjectID: subject.id, title: "Investigation", date: date, criterionA: 0, criterionB: 8)], events: [PlannerEventRecord(title: "Exam", subjectID: subject.id, kind: "Exam", startDate: date)])
}
@Test func backupRoundTripsEveryEntityAndUnicode() throws {
    var backup = sampleBackup(); backup.notes[0].body += "\n日本語 · x² · ∑"
    #expect(try BackupCodec.decode(BackupCodec.encode(backup)) == backup)
    #expect(backup.recordCount == 11)
}
@Test func ibWorkTypeSurvivesBackupWithoutChangingMYPCriteria() throws {
    var backup = sampleBackup()
    backup.assignments[0].ibWorkType = .personalProject
    #expect(backup.assignments[0].mypCriteria == ["A", "B"])
    var restored = try BackupCodec.decode(BackupCodec.encode(backup))
    #expect(restored.assignments[0].ibWorkType == .personalProject)
    #expect(restored.assignments[0].mypCriteria == ["A", "B"])
    restored.assignments[0].ibWorkType = .internalAssessment
    #expect(restored.assignments[0].ibWorkType == .internalAssessment)
}
@Test func backupRejectsUnsupportedVersion() {
    var backup = sampleBackup(); backup.version = 999
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
}
@Test func backupRejectsDuplicateIDs() {
    var backup = sampleBackup(); backup.subjects.append(backup.subjects[0])
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
}
@Test func backupRejectsOrphanedReferences() {
    var backup = sampleBackup(); backup.subjects = []
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
    backup = sampleBackup(); backup.cards[0].deckID = UUID()
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
    backup = sampleBackup(); backup.reviews[0].deckID = UUID()
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
}
@Test func backupRejectsOutOfRangeCriteriaButAcceptsZero() throws {
    var backup = sampleBackup()
    try BackupCodec.validate(backup)
    backup.assessments[0].criterionA = 9
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
    backup.assessments[0].criterionA = -1
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
}
@Test func backupRejectsInvalidSchedulesAndDurations() {
    var backup = sampleBackup(); backup.cards[0].ease = .infinity
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
    backup = sampleBackup(); backup.sessions[0].durationSeconds = -1
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
    backup = sampleBackup(); backup.assignments[0].reminderDate = backup.assignments[0].dueDate.addingTimeInterval(1)
    #expect(throws: BackupError.self) { try BackupCodec.validate(backup) }
}
@Test func malformedJSONFailsWithoutPartialData() {
    #expect(throws: (any Error).self) { try BackupCodec.decode(Data("not json".utf8)) }
}
