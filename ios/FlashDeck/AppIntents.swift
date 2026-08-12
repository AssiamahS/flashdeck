import AppIntents
import Foundation

// MARK: - Shared deck loading (cache-first so Siri answers fast)

enum DeckData {
    static func loadFile() async throws -> DeckFile {
        if let cached = UserDefaults.standard.data(forKey: "decksCache"),
           let file = try? JSONDecoder().decode(DeckFile.self, from: cached) {
            return file
        }
        let (data, _) = try await URLSession.shared.data(from: DeckStore.rawURL)
        let file = try JSONDecoder().decode(DeckFile.self, from: data)
        UserDefaults.standard.set(data, forKey: "decksCache")
        return file
    }

    static func deck(id: String) async throws -> Deck {
        guard let deck = try await loadFile().decks.first(where: { $0.id == id }),
              !deck.cards.isEmpty else {
            throw QuizError.deckNotFound
        }
        return deck
    }
}

enum QuizError: Error, CustomLocalizedStringResourceConvertible {
    case deckNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .deckNotFound: "I couldn't find that deck. Open Flash Deck once to refresh your decks."
        }
    }
}

// MARK: - Deck entity (lets Siri phrases carry a deck name, e.g. "quiz me on countries")

struct DeckEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Deck")
    static let defaultQuery = DeckQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct DeckQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DeckEntity] {
        try await Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DeckEntity] {
        try await Self.all()
    }

    static func all() async throws -> [DeckEntity] {
        try await DeckData.loadFile().decks.map { DeckEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - One-shot quiz: Siri reads a card, listens for your answer, grades it

struct QuizMeIntent: AppIntent {
    static let title: LocalizedStringResource = "Quiz Me"
    static let description = IntentDescription("Siri reads one flashcard, takes your spoken answer, and grades it.")

    @Parameter(title: "Deck", requestValueDialog: "Which deck?") var deck: DeckEntity
    @Parameter(title: "Answer") var answer: String?

    private static let pendingKey = "siriPendingCard"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults.standard

        // Second entry: Siri captured the spoken answer for the card we asked.
        if let answer,
           let pending = defaults.dictionary(forKey: Self.pendingKey) as? [String: String],
           let deckID = pending["deckID"], let front = pending["front"], let back = pending["back"] {
            defaults.removeObject(forKey: Self.pendingKey)
            let correct = Self.matches(answer, back)
            let boxKey = "\(deckID)|\(front)"
            var boxes = defaults.dictionary(forKey: "leitner") as? [String: Int] ?? [:]
            let current = boxes[boxKey] ?? 1
            boxes[boxKey] = correct ? min(current + 1, 5) : 1
            defaults.set(boxes, forKey: "leitner")
            let dialog: IntentDialog = correct
                ? "Correct! \(back)."
                : "Not quite — it's \(back)."
            return .result(dialog: dialog)
        }

        // First entry: pick a due card from the deck, then ask the question.
        let fullDeck = try await DeckData.deck(id: deck.id)
        let boxes = defaults.dictionary(forKey: "leitner") as? [String: Int] ?? [:]
        guard let card = fullDeck.cards.shuffled()
            .min(by: { (boxes["\(fullDeck.id)|\($0.front)"] ?? 1) < (boxes["\(fullDeck.id)|\($1.front)"] ?? 1) }) else {
            throw QuizError.deckNotFound
        }
        defaults.set(["deckID": fullDeck.id, "front": card.front, "back": card.back], forKey: Self.pendingKey)
        throw $answer.needsValueError(IntentDialog("\(card.front)?"))
    }

    /// Forgiving spoken-answer match: case/punctuation-insensitive, and accepts
    /// the answer inside a longer sentence ("it's Paris" matches "Paris").
    static func matches(_ spoken: String, _ expected: String) -> Bool {
        let a = normalize(spoken)
        let b = normalize(expected)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || (b.count >= 4 && b.contains(a) && a.count >= 4)
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Continuous quiz: background audio, card after card, CarPlay-friendly

struct ContinuousQuizIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Nonstop Quiz"
    static let description = IntentDescription("Hands-free audio quiz — reads card after card with a pause before each answer. Keeps going over CarPlay until you stop.")

    @Parameter(title: "Deck", requestValueDialog: "Which deck?") var deck: DeckEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let fullDeck = try await DeckData.deck(id: deck.id)
        try await VoiceQuizEngine.shared.start(deck: fullDeck)
        return .result(dialog: "Starting \(deck.name). I'll read a card, give you a moment, then say the answer. Use next to skip, pause to stop.")
    }
}

struct StopQuizIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Stop Quiz"
    static let description = IntentDescription("Stops the nonstop flashcard quiz.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await VoiceQuizEngine.shared.stop()
        return .result(dialog: "Quiz stopped.")
    }
}

// MARK: - Zero-setup Siri phrases (app name is required by Apple in every phrase)

struct FlashDeckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuizMeIntent(),
            phrases: [
                "Quiz me in \(.applicationName)",
                "Quiz me on \(\.$deck) in \(.applicationName)",
                "Quiz me on \(\.$deck) using \(.applicationName)",
                "Ask me a \(\.$deck) question in \(.applicationName)",
            ],
            shortTitle: "Quiz Me",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: ContinuousQuizIntent(),
            phrases: [
                "Keep quizzing me on \(\.$deck) in \(.applicationName)",
                "Nonstop quiz on \(\.$deck) in \(.applicationName)",
                "Nonstop quiz on \(\.$deck) using \(.applicationName)",
                "Drill me on \(\.$deck) in \(.applicationName)",
                "Start a nonstop quiz in \(.applicationName)",
            ],
            shortTitle: "Nonstop Quiz",
            systemImageName: "infinity.circle"
        )
        AppShortcut(
            intent: StopQuizIntent(),
            phrases: [
                "Stop the quiz in \(.applicationName)",
                "End the quiz in \(.applicationName)",
            ],
            shortTitle: "Stop Quiz",
            systemImageName: "stop.circle"
        )
    }
}
