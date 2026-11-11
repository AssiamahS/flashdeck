import AppIntents
import SwiftUI
import WidgetKit

// Lock Screen flash card: one question at a time, a new card every 15 minutes.
// Tap = show the answer, tap again = next card. Also offered on the Home Screen (small).

// MARK: - Cards that fit

struct FlashCard: Hashable {
    let front: String
    let back: String
    let deckID: String
    let deckName: String
    var key: String { "\(deckID)|\(front)" }
}

enum CardPool {
    static let allID = "__all__"
    /// Lock Screen space is tiny: only text cards that can actually be read there.
    static let maxFront = 140
    static let maxBack = 220

    static func cards(in decks: [Deck], deckID: String) -> [FlashCard] {
        let chosen = decks.filter { deckID == allID || $0.id == deckID }
        return (chosen.isEmpty ? decks : chosen).flatMap { deck in
            deck.cards.compactMap { card -> FlashCard? in
                let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
                let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
                guard card.image == nil, card.video == nil, card.backImage == nil,
                      !front.isEmpty, !back.isEmpty,
                      front.count <= maxFront, back.count <= maxBack else { return nil }
                return FlashCard(front: front, back: back, deckID: deck.id, deckName: deck.name)
            }
        }
    }

    /// Spread consecutive time slots across the deck (Knuth multiplicative hash).
    static func index(slot: Int, count: Int) -> Int {
        Int((UInt64(truncatingIfNeeded: slot) &* 2_654_435_761) % UInt64(count))
    }
}

/// Tap state, shared by the flip intent and the provider (both run in the extension).
enum CardTapState {
    private static var defaults: UserDefaults { .standard }

    static var revealedKey: String? {
        get { defaults.string(forKey: "card.revealed") }
        set { defaults.set(newValue, forKey: "card.revealed") }
    }

    /// Cards skipped by tapping past an answer; shifts which card each slot shows.
    static var skip: Int {
        get { defaults.integer(forKey: "card.skip") }
        set { defaults.set(newValue, forKey: "card.skip") }
    }

    static func tap(_ key: String) {
        if revealedKey == key {
            revealedKey = nil
            skip += 1
        } else {
            revealedKey = key
        }
    }
}

// MARK: - Intents

struct CardDeckEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Deck"
    static let defaultQuery = CardDeckQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct CardDeckQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CardDeckEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CardDeckEntity] { await all() }

    func defaultResult() async -> CardDeckEntity? {
        CardDeckEntity(id: CardPool.allID, name: "All decks")
    }

    private func all() async -> [CardDeckEntity] {
        let decks = await WidgetDecks.loadCached()
            .filter { !CardPool.cards(in: [$0], deckID: $0.id).isEmpty }
        return [CardDeckEntity(id: CardPool.allID, name: "All decks")]
            + decks.map { CardDeckEntity(id: $0.id, name: $0.name) }
    }
}

struct CardWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Flash Card"
    static let description = IntentDescription("A new card every 15 minutes. Tap for the answer.")

    @Parameter(title: "Deck")
    var deck: CardDeckEntity?

    init() {}
}

struct FlipCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Flip Card"
    static let isDiscoverable = false

    @Parameter(title: "Card") var cardKey: String

    init() {}
    init(cardKey: String) { self.cardKey = cardKey }

    func perform() async throws -> some IntentResult {
        CardTapState.tap(cardKey)
        return .result()
    }
}

// MARK: - Timeline

struct CardEntry: TimelineEntry {
    let date: Date
    let card: FlashCard?
    let revealed: Bool
}

struct CardProvider: AppIntentTimelineProvider {
    static let slot: TimeInterval = 15 * 60
    private static let sample = FlashCard(front: "What does the 'S' in HTTPS stand for?", back: "Secure (HTTP over TLS)",
                                          deckID: "sample", deckName: "Flash Deck")

    func placeholder(in context: Context) -> CardEntry {
        CardEntry(date: .now, card: Self.sample, revealed: false)
    }

    func snapshot(for configuration: CardWidgetIntent, in context: Context) async -> CardEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entries(for: configuration, count: 1)[0]
    }

    func timeline(for configuration: CardWidgetIntent, in context: Context) async -> Timeline<CardEntry> {
        let list = await entries(for: configuration, count: 8)
        let next = list[list.count - 1].date.addingTimeInterval(Self.slot)
        return Timeline(entries: list, policy: .after(next))
    }

    private func entries(for configuration: CardWidgetIntent, count: Int) async -> [CardEntry] {
        let pool = CardPool.cards(in: await WidgetDecks.loadCached(),
                                  deckID: configuration.deck?.id ?? CardPool.allID)
        let now = Date.now
        guard !pool.isEmpty else { return [CardEntry(date: now, card: nil, revealed: false)] }

        let firstSlot = Int(now.timeIntervalSince1970 / Self.slot)
        let skip = CardTapState.skip
        let revealed = CardTapState.revealedKey
        return (0..<count).map { offset in
            let slot = firstSlot + offset
            let card = pool[CardPool.index(slot: slot + skip, count: pool.count)]
            let date = offset == 0 ? now : Date(timeIntervalSince1970: Double(slot) * Self.slot)
            return CardEntry(date: date, card: card, revealed: offset == 0 && card.key == revealed)
        }
    }
}

// MARK: - Views

struct CardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CardEntry

    var body: some View {
        if let card = entry.card {
            Button(intent: FlipCardIntent(cardKey: card.key)) {
                content(card)
            }
            .buttonStyle(.plain)
        } else {
            Text("No short cards yet. Edit the widget to pick a deck.")
                .font(.caption)
        }
    }

    private var hint: String { entry.revealed ? "Tap for the next card" : "Tap for the answer" }

    @ViewBuilder
    private func content(_ card: FlashCard) -> some View {
        switch family {
        case .accessoryInline:
            Text(entry.revealed ? card.back : card.front)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: entry.revealed ? "checkmark.seal.fill" : "rectangle.on.rectangle.angled")
                        .font(.caption2)
                    Text(entry.revealed ? card.back : card.front)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(card.deckName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(card.front)
                    .font(.system(size: 14, weight: .semibold))
                    .minimumScaleFactor(0.6)
                if entry.revealed {
                    Text(card.back)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct CardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FlashDeckCard", intent: CardWidgetIntent.self, provider: CardProvider()) { entry in
            CardWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Flash Card")
        .description("A new card every 15 minutes. Tap for the answer, tap again for the next card.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall])
    }
}
