import Foundation

/// One multiple-choice question built from a card.
/// Security+ style cards carry their options in the front ("A. …" lines) and the
/// correct option line(s) in the back; plain term/definition cards borrow three
/// other backs from the same deck as distractors.
struct QuizQuestion: Hashable {
    var card: Card
    var prompt: String
    var options: [String]
    var correct: Set<Int>

    /// "Select TWO" questions need every correct option picked before checking.
    var picksNeeded: Int { correct.count }
}

enum QuizBuilder {
    nonisolated(unsafe) private static let optionLine = #/^([A-H])\.\s*(.+)$/#

    /// Options parsed from "A. …" lines, or nil when the card isn't lettered multiple choice.
    static func lettered(_ card: Card) -> QuizQuestion? {
        var prompt: [String] = []
        var options: [(letter: Character, text: String)] = []
        for raw in card.front.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.wholeMatch(of: optionLine) {
                options.append((Character(String(m.1)), String(m.2)))
            } else if options.isEmpty {
                prompt.append(line)
            } else if !line.isEmpty {
                // wrapped option text continues the previous option
                options[options.count - 1].text += " " + line
            }
        }
        guard options.count >= 2 else { return nil }

        let answerLetters = card.back.split(separator: "\n").compactMap { raw -> Character? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            return line.wholeMatch(of: optionLine).map { Character(String($0.1)) }
        }
        let correct = Set(options.indices.filter { answerLetters.contains(options[$0].letter) })
        guard !correct.isEmpty else { return nil }

        return QuizQuestion(
            card: card,
            prompt: prompt.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            options: options.map(\.text),
            correct: correct
        )
    }

    /// Term → pick the right back out of four, distractors drawn from the rest of the deck.
    static func borrowed(_ card: Card, pool: [String]) -> QuizQuestion? {
        let answer = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !card.front.isEmpty else { return nil }
        let others = Array(Set(pool.filter { $0 != answer && !$0.isEmpty })).shuffled().prefix(3)
        guard others.count >= 2 else { return nil }
        let options = (Array(others) + [answer]).shuffled()
        return QuizQuestion(
            card: card,
            prompt: card.front,
            options: options,
            correct: [options.firstIndex(of: answer)!]
        )
    }

    /// Every card that can become a question, lettered cards first-class, others borrowed.
    static func questions(for deck: Deck) -> [QuizQuestion] {
        let pool = deck.cards.map { $0.back.trimmingCharacters(in: .whitespacesAndNewlines) }
        return deck.cards.compactMap { card in
            guard card.image == nil, card.backImage == nil, card.video == nil else { return nil }
            if let q = lettered(card) { return q }
            // lettered front whose answer key didn't parse: skip rather than guess
            let optionLines = card.front.split(separator: "\n").filter { $0.contains(optionLine) }
            return optionLines.count >= 2 ? nil : borrowed(card, pool: pool)
        }
    }

    static func canQuiz(_ deck: Deck) -> Bool {
        deck.cards.contains { $0.image == nil && $0.backImage == nil && $0.video == nil } && deck.cards.count >= 3
    }
}
