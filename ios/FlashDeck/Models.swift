import Foundation

struct Card: Codable, Hashable {
    var front: String
    var back: String
    var image: String?
    var video: String?
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

    // Leitner boxes 1-5, keyed by deck id + card front, same grading the Echo skill uses
    private var boxes: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "leitner") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "leitner") }
    }

    func box(deck: Deck, card: Card) -> Int {
        boxes["\(deck.id)|\(card.front)"] ?? 1
    }

    func setBox(_ value: Int, deck: Deck, card: Card) {
        var all = boxes
        all["\(deck.id)|\(card.front)"] = min(max(value, 1), 5)
        boxes = all
        objectWillChange.send()
    }

    func masteredCount(_ deck: Deck) -> Int {
        deck.cards.filter { box(deck: deck, card: $0) >= 5 }.count
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
        } catch {
            if let cached = UserDefaults.standard.data(forKey: "decksCache"),
               let file = try? JSONDecoder().decode(DeckFile.self, from: cached) {
                decks = file.decks
            }
            errorMessage = "Couldn't refresh decks: \(error.localizedDescription)"
        }
    }
}
