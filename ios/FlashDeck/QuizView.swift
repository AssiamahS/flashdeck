import SwiftUI

/// Multiple-choice practice test: points, progress bar, colored answer tiles.
/// Every answer also grades the card's Leitner box, same as a swipe in StudyView.
/// After each answer an explanation card says why the key is right (and why the
/// picked option was wrong); read-aloud speaks question, options and verdict.
struct QuizView: View {
    @EnvironmentObject var store: DeckStore
    @ObservedObject private var speaker = CardSpeaker.shared
    @AppStorage("quizAutoNext") private var autoNext = true
    let deck: Deck

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var picked: Set<Int> = []
    @State private var checked = false
    @State private var points = 0
    @State private var missed: [QuizQuestion] = []
    @State private var askOpen = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    autoNext.toggle()
                } label: {
                    Image(systemName: autoNext ? "forward.fill" : "forward")
                }
                .accessibilityLabel(autoNext ? "Auto-next on correct: on" : "Auto-next on correct: off")
                .accessibilityIdentifier("quizAutoNext")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    speaker.enabled.toggle()
                    if speaker.enabled { readCurrent() }
                } label: {
                    Image(systemName: speaker.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(speaker.enabled ? "Mute read-aloud" : "Unmute read-aloud")
                .accessibilityIdentifier("quizSpeaker")
            }
        }
        .onAppear { if questions.isEmpty { start(with: ordered()) } }
        .onDisappear { speaker.release() }
        // Auto-next waits for the verdict to finish being read out.
        .onChange(of: speaker.speaking) { _, now in
            if !now, speaker.enabled { autoAdvanceIfRight() }
        }
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
                    if checked {
                        explanation(q)
                        AskBox(question: q, picked: picked, open: $askOpen)
                            .id(index)
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
                .buttonStyle(.plain)
                .disabled(!checked && picked.count != q.picksNeeded)
                .opacity(!checked && picked.count != q.picksNeeded ? 0.35 : 1)
                .accessibilityIdentifier("quizNext")
                // Return belongs to the Ask field while it's open
                .keyboardShortcut(askOpen ? nil : KeyboardShortcut(.return, modifiers: []))
            }
        }
        .padding()
    }

    private func optionTile(_ q: QuizQuestion, _ i: Int) -> some View {
        let isRight = q.correct.contains(i)
        let isPicked = picked.contains(i)
        let color = Self.palette[i % Self.palette.count]
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
                Text(QuizBuilder.label(q, i))
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
            .background(color, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white, lineWidth: isPicked ? 3 : 0)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(q.letters.indices.contains(i) ? q.letters[i].lowercased() : "\(i + 1)")), modifiers: [])
        .accessibilityIdentifier("quizOption\(i)")
    }

    /// Green "what you got right" or red "why that was wrong", plus the key's reason.
    private func explanation(_ q: QuizQuestion) -> some View {
        let right = picked == q.correct
        let wrongPicks = picked.subtracting(q.correct).sorted()
        let answer = q.correct.sorted().map { QuizBuilder.label(q, $0) }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 10) {
            Label(right ? "Correct" : "Not quite", systemImage: right ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(right ? .green : .red)
            if !right {
                ForEach(wrongPicks, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You picked \(QuizBuilder.label(q, i))").font(.subheadline.weight(.semibold))
                        if let why = QuizBuilder.whyNot(q, picked: i) {
                            Text(why).font(.subheadline)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(right ? answer : "Answer: \(answer)").font(.subheadline.weight(.semibold))
                if let why = q.card.why {
                    Text(why).font(.subheadline)
                }
            }
            if let doubt = q.card.keyDoubt {
                Label(doubt, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background((right ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quizExplanation")
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
        readCurrent()
    }

    private func check(_ q: QuizQuestion) {
        guard !checked, picked.count == q.picksNeeded else { return }
        checked = true
        let right = picked == q.correct
        if right { points += 1 } else { missed.append(q) }
        store.grade(deck: deck, card: q.card, got: right)
        Haptics.verdict(success: right)
        if speaker.enabled {
            speaker.speak(verdict(q, right: right))
        } else if right && autoNext {
            let at = index
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if index == at { autoAdvanceIfRight() }
            }
        }
    }

    private func advance() {
        index += 1
        picked = []
        checked = false
        askOpen = false
        readCurrent()
    }

    private func autoAdvanceIfRight() {
        guard autoNext, !askOpen, checked, index < questions.count, picked == questions[index].correct else { return }
        advance()
    }

    // MARK: read-aloud

    private func readCurrent() {
        guard speaker.enabled, index < questions.count else {
            speaker.stop()
            return
        }
        let q = questions[index]
        let options = q.options.indices.map { QuizBuilder.label(q, $0) }
        speaker.speak(([q.prompt] + options).joined(separator: "\n"))
    }

    private func verdict(_ q: QuizQuestion, right: Bool) -> String {
        let answer = q.correct.sorted().map { QuizBuilder.label(q, $0) }.joined(separator: ", and ")
        var lines = [right ? "Correct. \(answer)" : "Wrong."]
        if !right {
            for i in picked.subtracting(q.correct).sorted() {
                lines.append("You picked \(QuizBuilder.label(q, i))")
                if let why = QuizBuilder.whyNot(q, picked: i) { lines.append(why) }
            }
            lines.append("The answer is \(answer)")
        }
        if let why = q.card.why { lines.append(why) }
        return lines.joined(separator: "\n")
    }
}

/// "Ask about this": follow-up questions on the card on screen, answered by the
/// flashdeck-relay Worker (Workers AI). Answers are read aloud when read-aloud is on.
private struct AskBox: View {
    let question: QuizQuestion
    let picked: Set<Int>
    @Binding var open: Bool

    @State private var text = ""
    @State private var turns: [(ask: String, answer: String)] = []
    @State private var busy = false
    @FocusState private var focused: Bool

    private static let endpoint = URL(string: "https://flashdeck-relay.sylvesterassiamahpm.workers.dev/explain")!

    var body: some View {
        if !open {
            Button {
                open = true
                focused = true
            } label: {
                Label("Ask about this question", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.teal)
            .accessibilityIdentifier("quizAskOpen")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(turns.indices, id: \.self) { i in
                    Text(turns[i].ask).font(.subheadline.weight(.semibold))
                    Text(turns[i].answer).font(.subheadline)
                }
                if busy { ProgressView().controlSize(.small) }
                HStack {
                    TextField("e.g. what's the difference between RPO and RTO?", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(send)
                        .accessibilityIdentifier("quizAskField")
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.teal)
                    .disabled(busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func send() {
        let ask = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty, !busy else { return }
        text = ""
        busy = true
        let q = question
        let body: [String: Any] = [
            "question": ([q.prompt] + q.options.indices.map { QuizBuilder.label(q, $0) }).joined(separator: "\n"),
            "answer": q.correct.sorted().map { QuizBuilder.label(q, $0) }.joined(separator: ", "),
            "picked": picked.sorted().map { QuizBuilder.label(q, $0) }.joined(separator: ", "),
            "why": q.card.why ?? "",
            "ask": ask,
            "history": turns.map { ["ask": $0.ask, "answer": $0.answer] },
        ]
        Task {
            let answer = await Self.post(body)
            turns.append((ask, answer))
            busy = false
            if CardSpeaker.shared.enabled { CardSpeaker.shared.speak(answer) }
        }
    }

    private static func post(_ body: [String: Any]) async -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json?["answer"] ?? json?["error"]) as? String ?? "No answer — try again."
        } catch {
            return "Couldn’t reach the tutor — check your connection."
        }
    }
}
