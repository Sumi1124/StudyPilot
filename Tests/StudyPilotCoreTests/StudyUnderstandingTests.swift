import Foundation
import Testing
@testable import StudyPilotCore

@Test func mathQueriesFindQuadraticTasksWithoutLiteralMathTitle() {
    let items = [StudyContextItem(id: "bio", title: "Photosynthesis lab", subject: "Sciences"), StudyContextItem(id: "quad", title: "Quadratic equations", subject: "Mathematics"), StudyContextItem(id: "eng", title: "Macbeth essay", subject: "English")]
    let result = StudyUnderstanding.ranked(items, query: "what math tasks do I have?")
    #expect(result.map(\.id) == ["quad"])
    #expect(StudyUnderstanding.ranked([.init(id: "unlabelled", title: "Quadratic formula")], query: "math task").first?.id == "unlabelled")
}
@Test func topicAndTitleMatchingToleratesMinorSpellingMistakes() {
    #expect(StudyUnderstanding.topics(in: "quadrtic homework").contains("Mathematics"))
    #expect(StudyUnderstanding.score(query: "quadrtic", title: "Quadratic equations") > 0)
    #expect(StudyUnderstanding.similar("quadrtaic", "quadratic"))
    #expect(!StudyUnderstanding.similar("design", "biology"))
    #expect(StudyUnderstanding.ranked([.init(id: "one", title: "Quadratic equations")], query: "qudartic task").count == 1)
}
@Test func subjectLabelsAndOtherTopicsGroundSearchWithoutOverclaiming() {
    #expect(StudyUnderstanding.topics(in: "photosynthesis lab").contains("Sciences"))
    #expect(StudyUnderstanding.topics(in: "Macbeth essay").contains("English"))
    #expect(StudyUnderstanding.topics(in: "二次方程式").contains("Mathematics"))
    #expect(StudyUnderstanding.subjectHint(title: "Quadratic", subject: "Maths AA") == "Maths AA")
    #expect(StudyUnderstanding.subjectHint(title: "Quadratic").contains("inferred"))
    #expect(StudyUnderstanding.subjectHint(title: "My project").isEmpty)
}
@Test func followupRetrievalRemembersTheReferencedTaskAndChangesSubjectWhenAsked() {
    let history = [StudyChatMessage(role: "user", text: "Which math task should I do?"), .init(role: "assistant", text: "Your Quadratic equations task is due first."), .init(role: "user", text: "move it to tomorrow at 5pm")]
    let query = StudyUnderstanding.query(messages: history)
    #expect(query.contains("Quadratic equations")); #expect(query.contains("math"))
    var changed = history; changed[2].text = "what about science instead?"
    #expect(StudyUnderstanding.query(messages: changed) == "what about science instead?")
}
@Test func explicitSubjectPreventsBroadMisclassificationAndGenericTaskQueriesStillWork() {
    let items = [StudyContextItem(id: "science", title: "Quadratic trend in biology", subject: "Sciences"), .init(id: "math", title: "Algebra", subject: "Mathematics")]
    #expect(StudyUnderstanding.ranked(items, query: "math tasks").map(\.id) == ["math"])
    #expect(StudyUnderstanding.ranked(items, query: "what assignments do I have?").count == 2)
}
@Test func studyContextIsBoundedAndUsesRealTitlesAndSubjectHints() throws {
    let items = (0..<30).map { StudyContextItem(id: "\($0)", title: "Quadratic equations \($0)", subject: "Mathematics", details: String(repeating: "Read carefully. ", count: 100)) }
    let (summary, included) = try StudyUnderstanding.summary(items: items, query: "math tasks")
    #expect(included > 0 && included < items.count)
    #expect(summary.contains("Quadratic equations")); #expect(summary.utf8.count < 2100)
    #expect(!summary.contains(String(repeating: "Read carefully. ", count: 100)))
}
@Test func longRepliesDoNotErasePreviousUserContextForShortFollowups() throws {
    let messages = [StudyChatMessage(role: "user", text: "My Quadratic equations task is the one I mean."), .init(role: "assistant", text: String(repeating: "A detailed explanation. ", count: 300)), .init(role: "user", text: "move it to tomorrow at five")]
    let prompt = try StudyChat.prompt(messages: messages, calendarSnapshot: String(repeating: "x", count: 2400))
    #expect(prompt.contains("My Quadratic equations task")); #expect(prompt.contains("move it to tomorrow at five"))
    #expect(prompt.utf8.count < 7000)
}
@Test func taskRequestsPreferAssignmentsOverRelatedNotes() {
    let items = [StudyContextItem(id: "note", title: "Mathematics quadratic guide", subject: "Mathematics", kind: "Note title"), .init(id: "task", title: "Quadratic equations", subject: "Mathematics")]
    #expect(StudyUnderstanding.ranked(items, query: "what math tasks do I have?").map(\.id) == ["task"])
    #expect(StudyUnderstanding.ranked(items, query: "find my math notes").map(\.id) == ["note"])
}
@Test func pronounsAnchorToTheMostRecentExplicitSubject() {
    let messages = [StudyChatMessage(role: "user", text: "Find my math task"), .init(role: "assistant", text: "Quadratic equations"), .init(role: "user", text: "Now show my science task"), .init(role: "assistant", text: "Photosynthesis lab"), .init(role: "user", text: "move that tomorrow")]
    let query = StudyUnderstanding.query(messages: messages)
    #expect(query.contains("science")); #expect(query.contains("Photosynthesis")); #expect(!query.contains("math"))
}
@Test func ordinaryTaskQuestionsCannotTriggerCalendarMoveSelection() {
    for text in ["What math task do I have?", "Explain quadratic equations", "How do I move an event?", "Don't move that", "Do not reschedule it"] {
        #expect(!StudyUnderstanding.requestsMove(messages: [.init(role: "user", text: text)]))
    }
    for text in ["Move it to tomorrow at 5pm", "Can you reschejule my math session?", "Postpone this until Friday"] {
        #expect(StudyUnderstanding.requestsMove(messages: [.init(role: "user", text: text)]))
    }
    #expect(StudyUnderstanding.requestsMove(messages: [.init(role: "user", text: "Reschedule my study block"), .init(role: "assistant", text: "What time?"), .init(role: "user", text: "Tomorrow instead")]))
}
