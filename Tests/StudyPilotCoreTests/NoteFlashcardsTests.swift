import Testing
@testable import StudyPilotCore
@Test func noteCardsSkipMalformedAndDuplicateLines() {
    let cards = NoteFlashcards.parse("Heading\n What is energy? :: Capacity to do work\nwhat is energy? :: capacity to do work\nEmpty :: \n:: Empty\nTime :: 10::30")
    #expect(cards.count == 2)
    #expect(cards[0].question == "What is energy?")
    #expect(cards[1].answer == "10::30")
}
