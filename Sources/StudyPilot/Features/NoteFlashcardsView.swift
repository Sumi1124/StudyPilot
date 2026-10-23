import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct NoteFlashcardsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Deck.title) private var decks: [Deck]
    let subjectID: UUID?
    let source: String
    @State private var drafts: [NoteFlashcardDraft]
    @State private var deckID: UUID?
    @State private var title: String
    @State private var error: String?
    init(title: String, source: String, subjectID: UUID?) {
        self.source = source; self.subjectID = subjectID
        _title = State(initialValue: title.isEmpty ? "Study notes" : title)
        let parsed = NoteFlashcards.parse(source)
        _drafts = State(initialValue: parsed.isEmpty ? [NoteFlashcardDraft()] : Array(parsed.prefix(100)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Turn notes into flashcards").font(.title2.bold())
            Text("Lines written as Question :: Answer become editable cards. You can also write cards below while referring to your note.").font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("Show source note") { ScrollView { Text(source).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120) }
            Picker("Save to", selection: $deckID) {
                Text("New deck").tag(nil as UUID?)
                ForEach(decks) { Text($0.title).tag(Optional($0.id)) }
            }
            if deckID == nil { TextField("New deck name", text: $title).textFieldStyle(.roundedBorder) }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text("QUESTION").font(.caption.bold()); Spacer(); Button("Remove") { drafts.removeAll { $0.id == draft.id } } }
                            TextField("Question", text: $draft.question, axis: .vertical).textFieldStyle(.roundedBorder)
                            Text("ANSWER").font(.caption.bold())
                            TextField("Answer", text: $draft.answer, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...6)
                        }.pilotCard()
                    }
                }
            }
            Button("Add another card", systemImage: "plus") { drafts.append(NoteFlashcardDraft()) }.disabled(drafts.count >= 100)
            Text("Up to 100 cards per batch. Matching question-and-answer pairs already in the deck are skipped.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save cards & open deck", action: save).buttonStyle(.borderedProminent)
                    .disabled(drafts.isEmpty || !drafts.allSatisfy(\.isValid) || (deckID == nil && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(24).frame(width: 650, height: 720)
    }
    private func save() {
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        do {
            let destination: UUID
            if let deckID {
                guard try transaction.fetch(FetchDescriptor<Deck>()).contains(where: { $0.id == deckID }) else { error = "This deck was removed. Choose another deck."; return }
                destination = deckID
            } else {
                let deck = Deck(DeckRecord(title: title.trimmingCharacters(in: .whitespacesAndNewlines), subjectID: subjectID))
                destination = deck.id; transaction.insert(deck)
            }
            let existing = try transaction.fetch(FetchDescriptor<Flashcard>()).filter { $0.deckID == destination }
            var seen = Set(existing.map { NoteFlashcardDraft(question: $0.question, answer: $0.answer).key })
            for draft in drafts where draft.isValid {
                guard seen.insert(draft.key).inserted else { continue }
                transaction.insert(Flashcard(FlashcardRecord(deckID: destination, question: draft.question.trimmingCharacters(in: .whitespacesAndNewlines), answer: draft.answer.trimmingCharacters(in: .whitespacesAndNewlines))))
            }
            try transaction.save()
            Task { await ReminderService.shared.reconcile(context: context) }
            app.selectedDeckID = destination; app.section = .revision; dismiss()
        } catch { transaction.rollback(); self.error = "Cards could not be saved: \(error.localizedDescription)" }
    }
}
