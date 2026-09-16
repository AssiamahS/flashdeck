#if os(iOS)
import AppIntents
#endif
import Foundation

struct Card: Codable, Hashable {
    var front: String
    var back: String
    var image: String?
    var video: String?
    var backImage: String?
}

struct Deck: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var cards: [Card]
}

struct DeckFile: Codable {
    var decks: [Deck]
}

@MainActor
final class DeckStore: ObservableObject {
    @Published var decks: [Deck] = []
    @Published var loading = false
    @Published var errorMessage: String?

    static let rawURL = URL(string: "https://raw.githubusercontent.com/AssiamahS/flashdeck/main/decks.json")!

    private let sync = LeitnerSync()

    init() {
        sync.onSnapshot = { [weak self] boxes, learned in
            self?.applySnapshot(boxes: boxes, learned: learned)
        }
        sync.onGrade = { [weak self] key, box, learnedAt in
            self?.applyGrade(key: key, box: box, learnedAt: learnedAt)
        }
        sync.start()
    }

    // Leitner boxes 1-5, keyed by deck id + card front, same grading the Echo skill uses
    private var boxes: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "leitner") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "leitner") }
    }

    // When a card was last graded "got it" (epoch seconds, kept as Double: watch Int is 32-bit)
    private var learnedAt: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "learnedAt") as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "learnedAt") }
    }

    private static func key(_ deck: Deck, _ card: Card) -> String { "\(deck.id)|\(card.front)" }

    func box(deck: Deck, card: Card) -> Int {
        boxes[Self.key(deck, card)] ?? 1
    }

    func setBox(_ value: Int, deck: Deck, card: Card) {
        grade(deck: deck, card: card, got: value > box(deck: deck, card: card))
    }

    /// Got it: climb one box (max 5) and stamp the learned date. Missed: back to box 1.
    func grade(deck: Deck, card: Card, got: Bool) {
        let key = Self.key(deck, card)
        let next = got ? min(box(deck: deck, card: card) + 1, 5) : 1
        var all = boxes
        all[key] = next
        boxes = all
        var learned = learnedAt
        if got {
            learned[key] = Date().timeIntervalSince1970
            learnedAt = learned
        }
        lastDeckId = deck.id
        objectWillChange.send()
        sync.didGrade(key: key, box: next, learnedAt: got ? learned[key] : nil, boxes: all, learned: learned)
    }

    func masteredCount(_ deck: Deck) -> Int {
        deck.cards.filter { box(deck: deck, card: $0) >= 5 }.count
    }

    /// 0...1 — how far the deck has climbed through the five Leitner boxes.
    func progress(_ deck: Deck) -> Double {
        guard !deck.cards.isEmpty else { return 0 }
        let steps = deck.cards.reduce(0) { $0 + (box(deck: deck, card: $1) - 1) }
        return Double(steps) / Double(deck.cards.count * 4)
    }

    /// Cards graded "got it" in the last seven days.
    func learnedThisWeek() -> Int {
        let cutoff = Date().timeIntervalSince1970 - 7 * 86_400
        return learnedAt.values.filter { $0 >= cutoff }.count
    }

    var lastDeckId: String? {
        get { UserDefaults.standard.string(forKey: "lastDeck") }
        set { UserDefaults.standard.set(newValue, forKey: "lastDeck") }
    }

    var lastDeck: Deck? {
        guard let id = lastDeckId else { return nil }
        return decks.first { $0.id == id }
    }

    /// Full snapshot from the phone: boxes replace ours, learned dates merge by latest.
    private func applySnapshot(boxes remote: [String: Int], learned: [String: Double]) {
        boxes = remote
        mergeLearned(learned)
        objectWillChange.send()
    }

    /// One grade from the watch.
    private func applyGrade(key: String, box: Int, learnedAt at: Double?) {
        var all = boxes
        all[key] = box
        boxes = all
        if let at { mergeLearned([key: at]) }
        objectWillChange.send()
    }

    private func mergeLearned(_ incoming: [String: Double]) {
        var mine = learnedAt
        for (key, at) in incoming where at > (mine[key] ?? 0) { mine[key] = at }
        learnedAt = mine
    }

    func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        var request = URLRequest(url: Self.rawURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let file = try JSONDecoder().decode(DeckFile.self, from: data)
            decks = file.decks
            UserDefaults.standard.set(data, forKey: "decksCache")
            #if os(iOS)
            // Re-register deck names so "quiz me on <deck> in Flash Deck" tracks decks.json.
            FlashDeckShortcuts.updateAppShortcutParameters()
            #endif
        } catch {
            if let cached = UserDefaults.standard.data(forKey: "decksCache"),
               let file = try? JSONDecoder().decode(DeckFile.self, from: cached) {
                decks = file.decks
            }
            errorMessage = "Couldn't refresh decks: \(error.localizedDescription)"
        }
    }
}
