import SwiftUI

/// Multiple-choice practice test: points, progress bar, colored answer tiles.
/// Every answer also grades the card's Leitner box, same as a swipe in StudyView.
struct QuizView: View {
    @EnvironmentObject var store: DeckStore
    let deck: Deck

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var picked: Set<Int> = []
    @State private var checked = false
    @State private var points = 0
    @State private var missed: [QuizQuestion] = []

    private static let palette: [Color] = [.teal, .green, .orange, .red, .purple, .blue, .pink, .indigo]

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView("No questions", systemImage: "list.bullet.clipboard",
                                       description: Text("This deck has no text cards to quiz on."))
            } else if index >= questions.count {
                summary
            } else {
                question(questions[index])
            }
        }
        .navigationTitle(deck.name)
        .inlineTitleBar()
        .onAppear { if questions.isEmpty { start(with: ordered()) } }
    }

    // MARK: question screen

    private func question(_ q: QuizQuestion) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Points: \(points)/\(index + (checked ? 1 : 0))")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("quizPoints")
                Spacer()
                Text("\(index + 1) / \(questions.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(index + (checked ? 1 : 0)), total: Double(questions.count))
                .tint(.pink)

            ScrollView {
                VStack(spacing: 12) {
                    Text(q.prompt)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    if q.picksNeeded > 1 && !checked {
                        Text("Pick \(q.picksNeeded)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(q.options.indices, id: \.self) { i in
                        optionTile(q, i)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    if checked { advance() } else { check(q) }
                } label: {
                    Image(systemName: checked ? "arrow.right" : "checkmark")
                        .font(.title3.weight(.bold))
                        .frame(width: 52, height: 52)
                        .foregroundStyle(.white)
                        .background(Circle().fill(.teal))
                }
                .disabled(!checked && picked.count != q.picksNeeded)
                .opacity(!checked && picked.count != q.picksNeeded ? 0.35 : 1)
                .accessibilityIdentifier("quizNext")
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
    }

    private func optionTile(_ q: QuizQuestion, _ i: Int) -> some View {
        let isRight = q.correct.contains(i)
        let isPicked = picked.contains(i)
        let color = Self.palette[i % Self.palette.count]
        let dimmed = checked && !isRight && !isPicked
        return Button {
            guard !checked else { return }
            if isPicked {
                picked.remove(i)
            } else if q.picksNeeded == 1 {
                picked = [i]
                check(q)
            } else if picked.count < q.picksNeeded {
                picked.insert(i)
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Text(q.options[i])
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if checked && isRight {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                } else if checked && isPicked {
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                } else if isPicked {
                    Image(systemName: "circle.inset.filled")
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(color.opacity(dimmed ? 0.3 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white, lineWidth: isPicked ? 3 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quizOption\(i)")
    }

    // MARK: end screen

    private var summary: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("\(points)/\(questions.count)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
            Text("\(Int((Double(points) / Double(questions.count) * 100).rounded()))% correct")
                .font(.title3)
                .foregroundStyle(points * 100 >= questions.count * 85 ? .green : .orange)
            Text("Aim for 85% before booking the exam.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if !missed.isEmpty {
                Button("Retry the \(missed.count) missed") { start(with: missed.shuffled()) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            Button("New test") { start(with: ordered()) }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: flow

    /// Weakest Leitner box first, shuffled within each box so tests don't repeat.
    private func ordered() -> [QuizQuestion] {
        QuizBuilder.questions(for: deck)
            .map { ($0, store.box(deck: deck, card: $0.card), Double.random(in: 0..<1)) }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }

    private func start(with list: [QuizQuestion]) {
        questions = list
        index = 0
        picked = []
        checked = false
        points = 0
        missed = []
    }

    private func check(_ q: QuizQuestion) {
        guard !checked, picked.count == q.picksNeeded else { return }
        checked = true
        let right = picked == q.correct
        if right { points += 1 } else { missed.append(q) }
        store.grade(deck: deck, card: q.card, got: right)
        Haptics.verdict(success: right)
    }

    private func advance() {
        index += 1
        picked = []
        checked = false
    }
}
