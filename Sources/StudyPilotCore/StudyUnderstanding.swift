import Foundation

public struct StudyContextItem: Equatable, Sendable {
    public let id: String
    public let title: String
    public let subject: String
    public let kind: String
    public let details: String
    public let due: Date?
    public init(id: String, title: String, subject: String = "", kind: String = "Assignment", details: String = "", due: Date? = nil) {
        self.id = id; self.title = title; self.subject = subject; self.kind = kind; self.details = details; self.due = due
    }
}
public enum StudyUnderstanding {
    public static let instructions = """
    Understand the user's meaning rather than requiring literal title matches. A math task can be called Quadratic equations, algebra, or trigonometry; photosynthesis is science; Macbeth is English/literature. Minor spelling mistakes such as quadrtic should not prevent finding a relevant task. Use provided real subject labels and relevant study items; inferred topics are helpful guesses, not new facts about assignment requirements. Do not ask what subject quadratic equations belong to. If the previous answer identified one task, a follow-up like 'move it' or 'explain that' refers to that task; preserve that conversational context. If several plausible tasks remain, ask one focused question offering their actual titles. Do not request the exact title when the match is clear. Study items and calendar events are different: an assignment due date does not prove a study session exists. You may describe assignments even when the calendar has no events. Only calendar E-IDs can be used in move proposals. Do not let an empty calendar distract you from an ordinary study question. No search matches does not prove the workspace is empty. Answer general study questions normally even when there are no relevant saved items. Never invent saved items or requirements. Be natural and helpful, without mentioning JSON, IDs, snapshots or internal matching in your reply.
    """
    private static let groups: [(String, [String])] = [
        ("Mathematics", ["math", "maths", "mathematics", "algebra", "quadratic", "quadratics", "equation", "polynomial", "parabola", "factorisation", "factorization", "trigonometry", "geometry", "calculus", "derivative", "integral", "probability", "statistics", "logarithm", "fraction", "vector", "matrix", "matrices", "simultaneous equations", "数学", "二次方程式", "代数", "幾何"]),
        ("Sciences", ["science", "sciences", "biology", "chemistry", "physics", "photosynthesis", "respiration", "ecosystem", "genetics", "dna", "mitosis", "osmosis", "diffusion", "stoichiometry", "molecule", "atomic", "acid", "alkali", "electrolysis", "newton", "kinematics", "velocity", "acceleration", "electricity", "科学", "理科", "生物", "化学", "物理"]),
        ("English", ["english", "literature", "literary", "poetry", "poem", "shakespeare", "macbeth", "hamlet", "romeo", "juliet", "rhetoric", "persuasive writing", "creative writing", "animal farm", "of mice and men", "英語", "文学"]),
        ("Individuals & Societies", ["history", "geography", "humanities", "societies", "civilization", "civilisation", "industrial revolution", "world war", "cold war", "tectonic", "urbanisation", "urbanization", "economics", "歴史", "地理", "社会"]),
        ("Design", ["design", "prototype", "prototyping", "cad", "ergonomic", "wireframe", "product design", "デザイン"]),
        ("Physical Education", ["pe", "physical education", "fitness", "volleyball", "basketball", "biomechanics", "体育"]),
        ("Japanese", ["japanese", "kanji", "hiragana", "katakana", "日本語", "漢字"]),
        ("Spanish", ["spanish", "espanol", "español", "スペイン語"]),
        ("French", ["french", "francais", "français", "フランス語"])
    ]
    private static let stop = Set("a an the my me i our your is are am do does did have has had what which when where can could would should please tell show find list give task tasks assignment assignments homework work upcoming remaining any s study session sessions event events calendar need want to for on in of at with and or it this that those them one ones about other move reschedule tomorrow today next week due".split(separator: " ").map(String.init))
    public static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    /// Small edit distance tolerates missing letters and adjacent transpositions without broad substring matches.
    public static func similar(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let a = Array(lhs), b = Array(rhs)
        let limit = min(a.count, b.count) >= 8 ? 2 : 1
        guard min(a.count, b.count) >= 5, abs(a.count - b.count) <= limit, max(a.count, b.count) <= 48 else { return false }
        var previous = Array(0...b.count), beforePrevious = previous
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(row[j - 1] + 1, previous[j] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { row[j] = min(row[j], beforePrevious[j - 2] + 1) }
            }
            beforePrevious = previous; previous = row
        }
        return previous[b.count] <= limit
    }
    public static func topics(in text: String) -> Set<String> {
        let words = tokens(text), normalized = words.joined(separator: " ")
        return Set(groups.compactMap { label, aliases in
            aliases.contains { alias in
                let parts = tokens(alias)
                if parts.count > 1 { return normalized.contains(parts.joined(separator: " ")) }
                return words.contains { similar($0, parts.first ?? alias) || (alias.unicodeScalars.contains { $0.value > 127 } && $0.contains(alias)) }
            } ? label : nil
        })
    }
    public static func subjectHint(title: String, subject: String = "") -> String {
        if !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return subject }
        let inferred = topics(in: title).sorted()
        return inferred.isEmpty ? "" : inferred.joined(separator: ", ") + " (inferred topic)"
    }
    public static func score(query: String, title: String, subject: String = "", details: String = "") -> Int {
        let wanted = tokens(query).filter { !stop.contains($0) }, titleWords = tokens(title)
        var value = wanted.reduce(0) { sum, word in sum + (titleWords.contains(word) ? 35 : titleWords.contains(where: { similar(word, $0) }) ? 25 : 0) }
        let queryTopics = topics(in: query)
        // A real subject label outranks an inferred topic. Titles may still match exact requested topics.
        let explicit = topics(in: subject), inferred = topics(in: title)
        if !queryTopics.isDisjoint(with: explicit.isEmpty ? inferred : explicit) { value += explicit.isEmpty ? 60 : 90 }
        if !queryTopics.isEmpty && !explicit.isEmpty && queryTopics.isDisjoint(with: explicit) && value == 0 { return 0 }
        let detailWords = Set(tokens(String(details.prefix(1000))))
        value += wanted.filter { detailWords.contains($0) }.count * 5
        return value
    }
    public static func query(messages: [StudyChatMessage]) -> String {
        guard let current = messages.last(where: { $0.role == "user" }) else { return "" }
        let words = Set(tokens(current.text))
        let followup = !words.isDisjoint(with: ["it", "that", "this", "them", "those", "one", "ones", "instead", "later", "earlier"])
        guard topics(in: current.text).isEmpty && (followup || words.subtracting(stop).count <= 1) else { return current.text }
        let priorQuestions = messages.dropLast().filter { $0.role == "user" }
        let anchor = priorQuestions.last(where: { !topics(in: $0.text).isEmpty }) ?? priorQuestions.last
        let previous = anchor.map { [String($0.text.prefix(240))] } ?? []
        let response = messages.dropLast().last(where: { $0.role == "assistant" }).map { String($0.text.prefix(350)) } ?? ""
        return ([current.text] + previous + [response]).joined(separator: "\n")
    }
    public static func requestsMove(messages: [StudyChatMessage]) -> Bool {
        guard let last = messages.last(where: { $0.role == "user" }) else { return false }
        let normalized = tokens(last.text).joined(separator: " ")
        let negatives = ["do not move", "don t move", "dont move", "do not reschedule", "don t reschedule", "cancel the move", "cancel that", "never move"]
        if negatives.contains(where: { normalized.contains($0) }) { return false }
        if normalized.hasPrefix("how do ") || normalized.hasPrefix("how to ") || normalized.hasPrefix("explain ") { return false }
        let words = Set(tokens(last.text))
        let direct = words.contains { word in ["move", "reschedule", "postpone", "shift", "push", "mvoe"].contains { similar(word, $0) } }
        if direct || normalized.contains("change the time") || normalized.contains("bring forward") { return true }
        let timingFollowup = !words.isDisjoint(with: ["tomorrow", "later", "earlier", "instead", "pm", "am"])
        guard timingFollowup, let prior = messages.dropLast().last(where: { $0.role == "user" }) else { return false }
        return tokens(prior.text).contains { word in ["move", "reschedule", "postpone", "shift"].contains { similar(word, $0) } }
    }
    public static func ranked(_ items: [StudyContextItem], query: String) -> [StudyContextItem] {
        let words = Set(tokens(query))
        let tasks = !words.isDisjoint(with: ["task", "tasks", "assignment", "assignments", "homework"])
        let notes = !words.isDisjoint(with: ["note", "notes"])
        let candidates = items.filter { tasks && !notes ? $0.kind == "Assignment" : notes && !tasks ? $0.kind.hasPrefix("Note") : true }
        let broad = tokens(query).allSatisfy { stop.contains($0) }
        return candidates.map { ($0, score(query: query, title: $0.title, subject: $0.subject, details: $0.details)) }
            .filter { $0.1 > 0 || (broad && $0.0.kind == "Assignment") }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.due != b.0.due { return (a.0.due ?? .distantFuture) < (b.0.due ?? .distantFuture) }
                return a.0.id < b.0.id
            }.map(\.0)
    }
    public static func summary(items: [StudyContextItem], query: String, maximumBytes: Int = 1700) throws -> (String, Int) {
        let matches = ranked(items, query: query)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var rows: [[String: String]] = []
        for item in matches.prefix(8) {
            var row = ["title": String(item.title.prefix(110)), "kind": item.kind, "subject": subjectHint(title: item.title, subject: item.subject)]
            if let due = item.due { row["due"] = formatter.string(from: due) }
            if !item.details.isEmpty { row["details"] = String(item.details.prefix(160)) }
            guard try encoder.encode(rows + [row]).count <= maximumBytes else { break }
            rows.append(row)
        }
        return ("RELEVANT STUDY ITEMS. Found \(matches.count) likely matches; included \(rows.count). These are real saved titles and subject labels. Inferred topics are suggestions, not changes to saved subjects. Assignments are deadlines, not movable study sessions.\n" + String(decoding: try encoder.encode(rows), as: UTF8.self), rows.count)
    }
}
