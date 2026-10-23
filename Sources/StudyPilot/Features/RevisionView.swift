import SwiftUI
import SwiftData
import StudyPilotCore
import StudyPilotData

struct RevisionView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Deck.title) private var decks: [Deck]
    @LiveQuery(sort: \Flashcard.dueDate) private var cards: [Flashcard]
    @LiveQuery private var reviews: [Review]
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    @State private var selectedID: UUID?
    @State private var addDeck = false
    @State private var editDeck: Deck?
    @State private var addCard = false
    @State private var editCard: Flashcard?
    @State private var practice = false
    @State private var deletingCard: Flashcard?
    @State private var deletingDeck: Deck?
    @State private var search = ""
    private var selected: Deck? { decks.first { $0.id == selectedID } }
    private var deckCards: [Flashcard] { cards.filter { $0.deckID == selectedID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Make it stick", title: "Revision", subtitle: "Small reviews today. Stronger recall tomorrow.")
                HStack {
                    Text("Your decks").font(.headline); Spacer()
                    Button("New deck", systemImage: "plus") { addDeck = true }.buttonStyle(.borderedProminent)
                }
                if decks.isEmpty { EmptyState(symbol: "rectangle.on.rectangle", title: "Build a little knowledge", message: "Create a deck and add your own questions. StudyPilot will schedule each card based on how well you remember it.").pilotCard() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 14) {
                    ForEach(decks) { deck in
                        let count = cards.filter { $0.deckID == deck.id }.count
                        let due = cards.filter { $0.deckID == deck.id && $0.dueDate <= app.now }.count
                        Button { selectedID = deck.id } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Image(systemName: "rectangle.on.rectangle.angled").font(.title2).foregroundStyle(Color.pilot); Spacer(); Text("\(due) due").font(.caption.bold()).foregroundStyle(Color.pilot) }
                                Text(deck.title).font(.headline).foregroundStyle(.primary)
                                SubjectBadge(subject: subjects.first { $0.id == deck.subjectID })
                                Text("\(count) cards").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).pilotCard()
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(selectedID == deck.id ? Color.pilot : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).contextMenu {
                            Button("Edit deck") { editDeck = deck }
                            Button("Delete deck…", role: .destructive) { deletingDeck = deck }
                        }
                    }
                }
                if let selected {
                    let history = reviews.filter { $0.deckID == selected.id }
                    let due = deckCards.filter { $0.dueDate <= app.now }
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selected.title).font(.title2.bold())
                            let accuracy = ReviewScheduler.accuracy(history.map(\.record))
                            Text(accuracy.map { "\(Int(($0 * 100).rounded()))% recall · \(history.count) reviews" } ?? "Your first review is the start of your progress.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit deck") { editDeck = selected }
                        Button("Add card", systemImage: "plus") { addCard = true }
                        Button("Review \(due.count) cards", systemImage: "play.fill") { practice = true }.buttonStyle(.borderedProminent).disabled(due.isEmpty)
                    }
                    if due.isEmpty, let next = deckCards.map(\.dueDate).min() { Text("Next review: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    TextField("Search this deck", text: $search).textFieldStyle(.roundedBorder)
                    VStack(spacing: 0) {
                        if deckCards.isEmpty { EmptyState(symbol: "plus.rectangle", title: "One question at a time", message: "Add your first question and answer to begin.") }
                        ForEach(deckCards.filter { search.isEmpty || "\($0.question) \($0.answer)".localizedCaseInsensitiveContains(search) }) { card in
                            HStack {
                                VStack(alignment: .leading, spacing: 7) { Text(card.question).font(.headline).lineLimit(2); Text(card.answer).foregroundStyle(.secondary).lineLimit(2) }
                                Spacer()
                                Text(card.dueDate <= app.now ? "Ready" : card.dueDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                Button("Edit") { editCard = card }
                            }.padding(.vertical, 14).contextMenu { Button("Delete card…", role: .destructive) { deletingCard = card } }
                            Divider()
                        }
                    }.pilotCard()
                }
            }.padding(30)
        }
        .onAppear { if let id = app.selectedDeckID { selectedID = id; app.selectedDeckID = nil } else if selectedID == nil { selectedID = decks.first?.id } }
        .onChange(of: app.selectedDeckID) { if let id = app.selectedDeckID { selectedID = id; app.selectedDeckID = nil } }
        .onChange(of: decks.count) { if selectedID == nil { selectedID = decks.first?.id } }
        .sheet(isPresented: $addDeck) { DeckEditor() }
        .sheet(item: $editDeck) { DeckEditor(deck: $0) }
        .sheet(isPresented: $addCard) { if let selectedID { FlashcardEditor(deckID: selectedID) } }
        .sheet(item: $editCard) { FlashcardEditor(deckID: $0.deckID, card: $0) }
        .sheet(isPresented: $practice) { ReviewSessionView(cards: deckCards.filter { $0.dueDate <= app.now }, title: selected?.title ?? "Review") }
        .alert("Delete this card?", isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } })) {
            Button("Cancel", role: .cancel) { deletingCard = nil }
            Button("Delete", role: .destructive) {
                if let card = deletingCard { for review in reviews where review.cardID == card.id { context.delete(review) }; context.delete(card); app.save(context) }
                deletingCard = nil
            }
        } message: { Text("The card and its review history will be removed.") }
        .alert("Delete this deck and all its cards?", isPresented: Binding(get: { deletingDeck != nil }, set: { if !$0 { deletingDeck = nil } })) {
            Button("Cancel", role: .cancel) { deletingDeck = nil }
            Button("Delete deck", role: .destructive) {
                if let deck = deletingDeck {
                    for card in cards where card.deckID == deck.id { context.delete(card) }
                    for review in reviews where review.deckID == deck.id { context.delete(review) }
                    if selectedID == deck.id { selectedID = nil }
                    context.delete(deck); app.save(context)
                }
                deletingDeck = nil
            }
        } message: { Text("This also removes the deck’s review history. This cannot be undone without a backup.") }
    }
}
struct DeckEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @LiveQuery(sort: \Subject.name) private var subjects: [Subject]
    let deck: Deck?
    @State private var draft: DeckRecord
    init(deck: Deck? = nil) { self.deck = deck; _draft = State(initialValue: deck?.record ?? DeckRecord()) }
    var body: some View {
        VStack(spacing: 0) {
            Text(deck == nil ? "New deck" : "Edit deck").font(.title2.bold()).padding(24)
            Form {
                TextField("Name", text: $draft.title)
                SubjectPicker(subjects: subjects, selection: $draft.subjectID)
                Toggle("Remind me when a review is due", isOn: $draft.reminderEnabled)
                if draft.reminderEnabled {
                    Picker("Review time", selection: $draft.reminderHour) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    Text("StudyPilot schedules the next reminder after opening the app or reviewing a card. Enable notifications in Settings.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            SheetActions(title: "Save deck", disabled: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }) {
                draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if let deck { deck.apply(draft) } else { context.insert(Deck(draft)) }
                if app.save(context) { dismiss() }
            }
        }.frame(width: 500, height: 400)
    }
}
struct FlashcardEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let card: Flashcard?
    @State private var draft: FlashcardRecord
    init(deckID: UUID, card: Flashcard? = nil) { self.card = card; _draft = State(initialValue: card?.record ?? FlashcardRecord(deckID: deckID)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(card == nil ? "New flashcard" : "Edit flashcard").font(.title2.bold())
            Text("QUESTION").font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: $draft.question).font(.body).frame(height: 120).border(.quaternary).accessibilityLabel("Question")
            Text("ANSWER").font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: $draft.answer).font(.body).frame(height: 150).border(.quaternary).accessibilityLabel("Answer")
            SheetActions(title: "Save card", disabled: draft.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cancel: { dismiss() }) {
                draft.question = draft.question.trimmingCharacters(in: .whitespacesAndNewlines); draft.answer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if let card { card.apply(draft) } else { context.insert(Flashcard(draft)) }
                if app.save(context) { dismiss() }
            }
        }.padding(24).frame(width: 570)
    }
}
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let cards: [Flashcard]
    let title: String
    @State private var index = 0
    @State private var revealed = false
    @State private var correct = 0
    @State private var error: String?
    var body: some View {
        VStack(spacing: 24) {
            HStack { Text(title).font(.headline); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            ProgressView(value: Double(index), total: Double(max(1, cards.count))).tint(.pilot)
            if index < cards.count {
                let card = cards[index]
                Text("CARD \(index + 1) OF \(cards.count)").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 24) {
                        Text(card.question).font(.system(size: 26, weight: .medium, design: .rounded)).multilineTextAlignment(.center).textSelection(.enabled)
                        if revealed { Divider(); MarkdownPreview(source: card.answer).frame(maxWidth: .infinity, alignment: .center) }
                    }.padding(25)
                }.frame(maxWidth: .infinity, minHeight: 260).background(Color.pilot.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                if revealed {
                    Text("How well did you remember?").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(Array(ReviewRating.allCases.enumerated()), id: \.element) { offset, rating in
                            Button { rate(rating) } label: {
                                VStack(spacing: 6) {
                                    Text("\(offset + 1) · \(rating.rawValue)").font(.headline)
                                    let next = ReviewScheduler.schedule(card.record, rating: rating, now: Date())
                                    Text(rating == .again ? "10 minutes" : "\(next.intervalDays) day\(next.intervalDays == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(8)
                            }.keyboardShortcut(KeyEquivalent(Character(String(offset + 1))), modifiers: [])
                        }
                    }
                } else { Button("Show answer") { revealed = true }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.space, modifiers: []) }
            } else {
                EmptyState(symbol: "checkmark.seal", title: "A little stronger than before.", message: "You reviewed \(index) cards and recalled \(correct). Your next reviews are scheduled automatically; cards marked Again return in 10 minutes.")
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(30).frame(width: 700, height: 650)
    }
    private func rate(_ rating: ReviewRating) {
        guard revealed, index < cards.count else { return }
        let card = cards[index]; let now = Date()
        let next = ReviewScheduler.schedule(card.record, rating: rating, now: now)
        card.apply(next)
        context.insert(Review(ReviewRecord(cardID: card.id, deckID: card.deckID, reviewedAt: now, rating: rating.rawValue, intervalDays: next.intervalDays)))
        do {
            try context.save(); Task { await ReminderService.shared.reconcile(context: context) }
            if rating != .again { correct += 1 }; index += 1; revealed = false
        } catch { context.rollback(); self.error = "The review was not saved. Please try again: \(error.localizedDescription)" }
    }
}
