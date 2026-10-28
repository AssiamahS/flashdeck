import Foundation

// Shared with the watch app and the widget extension (no DeckStore / LeitnerSync there).
struct Card: Codable, Hashable {
    var front: String
    var back: String
    var image: String?
    var video: String?
    var backImage: String?
    /// Practice-test explanations (tools/explain_cards.py): why the keyed answer is
    /// right, why each other letter is wrong, and a note when the key looks off.
    var why: String?
    var whyNot: [String: String]?
    var keyDoubt: String?
}

struct Deck: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var cards: [Card]
}

struct DeckFile: Codable {
    var decks: [Deck]
}
