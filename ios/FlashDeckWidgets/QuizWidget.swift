import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Decks (fetched straight from GitHub, cached for offline)

enum WidgetDecks {
    static let url = URL(string: "https://raw.githubusercontent.com/AssiamahS/flashdeck/main/decks.json")!
    static let fallbackDeck = "security-plus"

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("decks.json")
    }

    static func load() async -> [Deck] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let file = try? JSONDecoder().decode(DeckFile.self, from: data) {
            try? data.write(to: cacheFile)
            return file.decks
        }
        guard let data = try? Data(contentsOf: cacheFile),
              let file = try? JSONDecoder().decode(DeckFile.self, from: data) else { return [] }
        return file.decks
    }
}

// MARK: - Configuration: which practice test

struct DeckEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Practice Test"
    static let defaultQuery = DeckQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct DeckQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DeckEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DeckEntity] { await all() }

    func defaultResult() async -> DeckEntity? {
        let decks = await all()
        return decks.first { $0.id == WidgetDecks.fallbackDeck } ?? decks.first
    }

    private func all() async -> [DeckEntity] {
        await WidgetDecks.load()
            .filter { QuizBuilder.canQuiz($0) && !QuizStore.questions(for: $0).isEmpty }
            .map { DeckEntity(id: $0.id, name: $0.name) }
    }
}

struct QuizWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Practice Test"
    static let description = IntentDescription("Answer practice-test questions right on the Home Screen.")

    @Parameter(title: "Practice test")
    var deck: DeckEntity?

    init() {}
}

// MARK: - State (one open question per deck, kept in the extension's defaults)

struct StoredQuestion: Codable {
    var deckID: String
    var deckName: String
    var prompt: String
    var options: [String]
    var correct: Int
    var picked: Int?
    var answeredAt: Date?
}

enum QuizStore {
    /// Keep tiles readable: short prompt, short options, at most four.
    static let maxPrompt = 200
    static let maxOption = 45

    private static var defaults: UserDefaults { .standard }

    static func current(_ deck: String) -> StoredQuestion? {
        guard let data = defaults.data(forKey: "quiz.\(deck)") else { return nil }
        return try? JSONDecoder().decode(StoredQuestion.self, from: data)
    }

    static func save(_ q: StoredQuestion) {
        defaults.set(try? JSONEncoder().encode(q), forKey: "quiz.\(q.deckID)")
    }

    static func clear(_ deck: String) { defaults.removeObject(forKey: "quiz.\(deck)") }

    static func score(_ deck: String) -> (right: Int, total: Int) {
        let s = defaults.array(forKey: "quiz.score.\(deck)") as? [Int] ?? [0, 0]
        return (s.first ?? 0, s.count > 1 ? s[1] : 0)
    }

    static func answer(_ deck: String, choice: Int) {
        guard var q = current(deck), q.picked == nil else { return }
        q.picked = choice
        q.answeredAt = .now
        save(q)
        let s = score(deck)
        defaults.set([s.right + (choice == q.correct ? 1 : 0), s.total + 1], forKey: "quiz.score.\(deck)")
    }

    /// Single-answer questions short enough for a tile.
    static func questions(for deck: Deck) -> [QuizQuestion] {
        QuizBuilder.questions(for: deck).filter { q in
            q.picksNeeded == 1 && q.prompt.count <= maxPrompt
        }
    }

    static func make(_ deck: Deck) -> StoredQuestion? {
        for q in questions(for: deck).shuffled() {
            guard let right = q.correct.first else { continue }
            // Trim to four options, always keeping the right one, order unchanged.
            let others = q.options.indices.filter { $0 != right }.prefix(3)
            let keep = (Array(others) + [right]).sorted()
            let options = keep.map { q.options[$0] }
            guard options.allSatisfy({ $0.count <= maxOption }) else { continue }
            return StoredQuestion(deckID: deck.id, deckName: deck.name, prompt: q.prompt,
                                  options: options, correct: keep.firstIndex(of: right)!)
        }
        return nil
    }
}

// MARK: - Interactive buttons

struct AnswerQuizIntent: AppIntent {
    static let title: LocalizedStringResource = "Answer Question"
    static let isDiscoverable = false

    @Parameter(title: "Deck") var deckID: String
    @Parameter(title: "Choice") var choice: Int

    init() {}
    init(deckID: String, choice: Int) {
        self.deckID = deckID
        self.choice = choice
    }

    func perform() async throws -> some IntentResult {
        QuizStore.answer(deckID, choice: choice)
        return .result()
    }
}

struct NextQuizIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Question"
    static let isDiscoverable = false

    @Parameter(title: "Deck") var deckID: String

    init() {}
    init(deckID: String) { self.deckID = deckID }

    func perform() async throws -> some IntentResult {
        QuizStore.clear(deckID)
        return .result()
    }
}

// MARK: - Timeline

struct QuizEntry: TimelineEntry {
    let date: Date
    let question: StoredQuestion?
    let right: Int
    let total: Int
}

struct QuizProvider: AppIntentTimelineProvider {
    private static let sample = StoredQuestion(
        deckID: "sample", deckName: "Security Plus",
        prompt: "Which protocol encrypts web traffic?",
        options: ["HTTP", "HTTPS", "FTP", "Telnet"], correct: 1)

    func placeholder(in context: Context) -> QuizEntry {
        QuizEntry(date: .now, question: Self.sample, right: 0, total: 0)
    }

    func snapshot(for configuration: QuizWidgetIntent, in context: Context) async -> QuizEntry {
        context.isPreview ? placeholder(in: context) : await entry(for: configuration)
    }

    func timeline(for configuration: QuizWidgetIntent, in context: Context) async -> Timeline<QuizEntry> {
        // An answered question rolls over on its own after an hour; an open one waits for you.
        Timeline(entries: [await entry(for: configuration)], policy: .after(.now.addingTimeInterval(3600)))
    }

    private func entry(for configuration: QuizWidgetIntent) async -> QuizEntry {
        let deckID = configuration.deck?.id ?? WidgetDecks.fallbackDeck
        if let q = QuizStore.current(deckID),
           q.answeredAt.map({ Date.now.timeIntervalSince($0) < 3600 }) ?? true {
            return entry(q)
        }
        let decks = await WidgetDecks.load()
        guard let deck = decks.first(where: { $0.id == deckID }),
              let q = QuizStore.make(deck) else {
            return QuizEntry(date: .now, question: nil, right: 0, total: 0)
        }
        QuizStore.save(q)
        return entry(q)
    }

    private func entry(_ q: StoredQuestion) -> QuizEntry {
        let s = QuizStore.score(q.deckID)
        return QuizEntry(date: .now, question: q, right: s.right, total: s.total)
    }
}

// MARK: - Views

/// Same tile colors as the in-app practice test (QuizView.palette), in order.
private let tileColors: [Color] = [.teal, .green, .orange, .red]
private let letters = ["A", "B", "C", "D"]

struct QuizWidgetView: View {
    let entry: QuizEntry
    @Environment(\.widgetFamily) private var family

    private var large: Bool { family == .systemLarge }

    var body: some View {
        if let q = entry.question {
            VStack(alignment: .leading, spacing: large ? 10 : 6) {
                header(q)
                Text(q.prompt)
                    .font(.system(size: large ? 17 : 13, weight: .semibold))
                    .lineLimit(large ? 6 : 2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if large {
                    VStack(spacing: 7) {
                        ForEach(q.options.indices, id: \.self) { tile(q, $0) }
                    }
                } else {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            tile(q, 0)
                            if q.options.count > 1 { tile(q, 1) }
                        }
                        if q.options.count > 2 {
                            GridRow {
                                tile(q, 2)
                                if q.options.count > 3 { tile(q, 3) } else { Color.clear }
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "rectangle.stack.badge.questionmark").font(.title2)
                Text("No short questions in this deck yet.\nLong-press → Edit Widget to pick another practice test.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func header(_ q: StoredQuestion) -> some View {
        HStack(spacing: 6) {
            if let picked = q.picked {
                let right = picked == q.correct
                Label(right ? "Correct" : "Answer: \(letters[q.correct])",
                      systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(right ? .green : .red)
                Spacer()
                Button(intent: NextQuizIntent(deckID: q.deckID)) {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.teal))
                }
                .buttonStyle(.plain)
            } else {
                Text(q.deckName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if entry.total > 0 {
                    Text("\(entry.right)/\(entry.total)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tile(_ q: StoredQuestion, _ i: Int) -> some View {
        let answered = q.picked != nil
        let isRight = answered && i == q.correct
        let isWrongPick = answered && i == q.picked && i != q.correct
        return Button(intent: AnswerQuizIntent(deckID: q.deckID, choice: i)) {
            HStack(spacing: 6) {
                Text(letters[i])
                    .font(.system(size: 11, weight: .heavy))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.28)))
                Text(q.options[i])
                    .font(.system(size: large ? 14 : 12, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isRight {
                    Image(systemName: "checkmark.circle.fill")
                } else if isWrongPick {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tileColors[i % tileColors.count]))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white, lineWidth: isRight || isWrongPick ? 2.5 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuizWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FlashDeckQuiz", intent: QuizWidgetIntent.self, provider: QuizProvider()) { entry in
            QuizWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Practice Test")
        .description("Tap an answer, see if you got it, tap Next. Long-press → Edit Widget to pick the test.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct FlashDeckWidgets: WidgetBundle {
    var body: some Widget {
        QuizWidget()
    }
}
