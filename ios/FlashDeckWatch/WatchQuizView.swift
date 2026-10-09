import SwiftUI
import WatchKit

/// Practice test on the wrist: same questions as the phone (QuizBuilder),
/// one colored tile per answer, scroll with the crown, tap to answer.
/// Every answer grades the card's Leitner box and syncs to the phone like a flashcard grade.
struct WatchQuizView: View {
    @EnvironmentObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    let deck: Deck

    @State private var questions: [QuizQuestion] = []
    @State private var loaded = false
    @State private var index = 0
    @State private var picked: Set<Int> = []
    @State private var checked = false
    @State private var points = 0
    @State private var missed: [QuizQuestion] = []

    private static let palette: [Color] = [.teal, .green, .orange, .red, .purple, .blue, .pink, .indigo]
    private static let examBar = 85

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if questions.isEmpty {
                Text("No text cards to quiz on in this deck.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if index >= questions.count {
                summary
            } else {
                question(questions[index])
            }
        }
        .navigationTitle("Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { start(with: ordered()) } }
    }

    // MARK: question screen

    private func question(_ q: QuizQuestion) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(points)/\(index + (checked ? 1 : 0)) pts")
                            .font(.caption2.weight(.semibold))
                        Spacer()
                        Text("\(index + 1)/\(questions.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .id("top")
                    ProgressView(value: Double(index + (checked ? 1 : 0)), total: Double(questions.count))
                        .tint(.pink)

                    HStack(alignment: .top, spacing: 5) {
                        Text("Q")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(WatchTheme.question, in: Circle())
                        Text(q.prompt)
                            .font(q.prompt.count > 120 ? .footnote : .body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)

                    if q.picksNeeded > 1 && !checked {
                        Text("Pick \(q.picksNeeded) (\(picked.count) picked)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(q.options.indices, id: \.self) { i in
                        optionTile(q, i)
                    }

                    if checked {
                        Text(picked == q.correct ? "Correct" : "Missed")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(picked == q.correct ? WatchTheme.answer : .red)
                            .padding(.top, 2)
                    }
                    actionButton(q)
                        .id("action")
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: checked) { _, isChecked in
                if isChecked { withAnimation { proxy.scrollTo("action", anchor: .bottom) } }
            }
            .onChange(of: index) { _, _ in proxy.scrollTo("top", anchor: .top) }
        }
    }

    @ViewBuilder
    private func actionButton(_ q: QuizQuestion) -> some View {
        if checked {
            Button(index + 1 < questions.count ? "Next" : "Finish") { advance() }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .foregroundStyle(.black)
        } else if q.picksNeeded > 1 {
            Button("Check") { check(q) }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(picked.count != q.picksNeeded)
        }
    }

    private func optionTile(_ q: QuizQuestion, _ i: Int) -> some View {
        let isRight = q.correct.contains(i)
        let isPicked = picked.contains(i)
        let dimmed = checked && !isRight && !isPicked
        let color = Self.palette[i % Self.palette.count]
        return Button {
            tap(q, i)
        } label: {
            HStack(spacing: 6) {
                Text(q.options[i])
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if checked && isRight {
                    Image(systemName: "checkmark.circle.fill")
                } else if checked && isPicked {
                    Image(systemName: "xmark.circle.fill")
                } else if isPicked {
                    Image(systemName: "circle.inset.filled")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(color.opacity(dimmed ? 0.25 : 0.9), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white, lineWidth: isPicked ? 2.5 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: end screen

    private var summary: some View {
        let pct = Int((Double(points) / Double(questions.count) * 100).rounded())
        return ScrollView {
            VStack(spacing: 8) {
                Text("\(points)/\(questions.count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(pct)% correct")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pct >= Self.examBar ? WatchTheme.answer : .orange)
                Text("Aim for \(Self.examBar)% before the exam.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !missed.isEmpty {
                    Button("Retry \(missed.count) missed") { start(with: missed.shuffled()) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                Button("New test") { start(with: ordered()) }
                    .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: flow

    /// Weakest Leitner box first, shuffled within each box — same order rule as the phone.
    private func ordered() -> [QuizQuestion] {
        QuizBuilder.questions(for: deck)
            .map { ($0, store.box(deck: deck, card: $0.card), Double.random(in: 0..<1)) }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }

    private func start(with list: [QuizQuestion]) {
        questions = list
        loaded = true
        index = 0
        picked = []
        checked = false
        points = 0
        missed = []
        store.lastDeckId = deck.id
    }

    private func tap(_ q: QuizQuestion, _ i: Int) {
        guard !checked else { return }
        if picked.contains(i) {
            picked.remove(i)
        } else if q.picksNeeded == 1 {
            picked = [i]
            check(q)
        } else if picked.count < q.picksNeeded {
            picked.insert(i)
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func check(_ q: QuizQuestion) {
        guard !checked, picked.count == q.picksNeeded else { return }
        checked = true
        let right = picked == q.correct
        if right { points += 1 } else { missed.append(q) }
        store.grade(deck: deck, card: q.card, got: right)
        WKInterfaceDevice.current().play(right ? .success : .failure)
    }

    private func advance() {
        index += 1
        picked = []
        checked = false
    }
}
