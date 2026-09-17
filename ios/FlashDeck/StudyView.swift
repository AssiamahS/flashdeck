import SwiftUI
import AVKit
import UIKit

/// Tinder-style study: the deck is a stack, the top card flips on tap, swipe right = got it,
/// swipe left = missed it (flipped or not), hold = skip, undo brings the last card back.
struct StudyView: View {
    @EnvironmentObject var store: DeckStore
    let deck: Deck
    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var gotCount = 0
    @State private var missedCount = 0
    @State private var drag: CGSize = .zero
    @State private var flyingOff = false
    @State private var history: [Step] = []
    @ObservedObject private var speaker = CardSpeaker.shared

    /// One graded / skipped card, enough to put it back.
    private struct Step {
        let box: Int
        let learnedAt: Double?
        let verdict: Verdict
    }
    private enum Verdict { case got, missed, skipped }

    private static let commitDistance: CGFloat = 110
    private static let edgeReserve: CGFloat = 24   // leave the system back-swipe alone

    var body: some View {
        VStack(spacing: 14) {
            if index < queue.count {
                header
                stack
                controls
            } else {
                ContentUnavailableView {
                    Label("Deck complete", systemImage: "checkmark.seal")
                } description: {
                    Text("\(gotCount) got it · \(missedCount) missed")
                } actions: {
                    Button("Study again") { start() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    speaker.enabled.toggle()
                    if speaker.enabled { readCurrent() }
                } label: {
                    Image(systemName: speaker.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(speaker.enabled ? "Mute read-aloud" : "Unmute read-aloud")
            }
        }
        .onAppear {
            if queue.isEmpty { start() }
            readCurrent()
        }
        .onChange(of: flipped) { _, _ in readCurrent() }
        .onChange(of: index) { _, _ in readCurrent() }
        .onDisappear { speaker.release() }
    }

    // MARK: pieces

    private var header: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(index), total: Double(queue.count))
                .tint(.blue)
            Text("\(index + 1) / \(queue.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var stack: some View {
        let card = queue[index]
        let dx = drag.width
        let progress = min(abs(dx) / Self.commitDistance, 1)
        return ZStack {
            // the next card peeks out from behind so it reads as a deck
            if index + 1 < queue.count {
                CardFace(card: queue[index + 1], flipped: false)
                    .scaleEffect(0.94 + 0.06 * progress)
                    .offset(y: 14 - 14 * progress)
                    .opacity(0.7 + 0.3 * progress)
                    .allowsHitTesting(false)
            }
            CardFace(card: card, flipped: flipped)
                .overlay(alignment: .topTrailing) { speakerButton(card) }
                .overlay { stamps(dx: dx) }
                .rotationEffect(.degrees(Double(dx / 18)))
                .offset(drag)
                .onTapGesture {
                    withAnimation(.spring(duration: 0.35)) { flipped.toggle() }
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    skip()
                }
                .simultaneousGesture(swipe)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tap to flip. Swipe right for got it, left for missed it, hold to skip.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { fly(.missed) } label: {
                Image(systemName: "xmark").font(.title2.weight(.bold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.red)
            .accessibilityLabel("Missed it")

            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold)).frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.secondary)
            .disabled(history.isEmpty)
            .accessibilityLabel("Undo last card")

            Button { fly(.got) } label: {
                Image(systemName: "checkmark").font(.title2.weight(.bold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(.green)
            .accessibilityLabel("Got it")
        }
        .disabled(flyingOff)
    }

    private func speakerButton(_ card: Card) -> some View {
        // Read this side on demand — works even when auto-read is muted.
        Button {
            speaker.speaking ? speaker.stop() : speaker.speak(flipped ? card.back : card.front)
        } label: {
            Image(systemName: speaker.speaking ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel(speaker.speaking ? "Stop reading" : "Read card aloud")
    }

    /// GOT IT / MISSED stamps that fade in as the card moves.
    private func stamps(dx: CGFloat) -> some View {
        let p = min(abs(dx) / Self.commitDistance, 1)
        return ZStack {
            stamp("GOT IT", color: .green, angle: -14)
                .opacity(dx > 0 ? Double(p) : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            stamp("MISSED", color: .red, angle: 14)
                .opacity(dx < 0 ? Double(p) : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding(22)
        .allowsHitTesting(false)
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }

    // MARK: gestures

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard !flyingOff, value.startLocation.x > Self.edgeReserve else { return }
                let t = value.translation
                // direction lock: mostly-vertical drags belong to the card's scroll view
                guard abs(t.width) > abs(t.height) * 0.8 || drag != .zero else { return }
                drag = CGSize(width: t.width, height: t.height * 0.25)
            }
            .onEnded { value in
                guard !flyingOff, drag != .zero else { return }
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if dx > Self.commitDistance || predicted > Self.commitDistance * 2.5 {
                    fly(.got)
                } else if dx < -Self.commitDistance || predicted < -Self.commitDistance * 2.5 {
                    fly(.missed)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { drag = .zero }
                }
            }
    }

    /// Throw the card off screen, then grade it and bring the next one up.
    private func fly(_ verdict: Verdict) {
        guard !flyingOff, index < queue.count, verdict != .skipped else { return }
        flyingOff = true
        let dir: CGFloat = verdict == .got ? 1 : -1
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(verdict == .got ? .success : .error)
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: dir * 700, height: drag.height + 40)
        } completion: {
            grade(got: verdict == .got)
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { drag = .zero }
            flyingOff = false
        }
    }

    // MARK: study logic

    /// Auto-read the visible side whenever a new card or the answer shows (if not muted).
    private func readCurrent() {
        guard speaker.enabled, index < queue.count else {
            speaker.stop()
            return
        }
        let card = queue[index]
        speaker.speak(flipped ? card.back : card.front)
    }

    private func start() {
        // Leitner: lowest boxes (least known) come first
        queue = deck.cards.sorted {
            store.box(deck: deck, card: $0) < store.box(deck: deck, card: $1)
        }
        index = 0
        flipped = false
        gotCount = 0
        missedCount = 0
        history = []
        drag = .zero
    }

    private func grade(got: Bool) {
        let card = queue[index]
        history.append(Step(box: store.box(deck: deck, card: card),
                            learnedAt: store.learnedStamp(deck: deck, card: card),
                            verdict: got ? .got : .missed))
        store.grade(deck: deck, card: card, got: got)
        if got { gotCount += 1 } else { missedCount += 1 }
        advance()
    }

    private func skip() {
        guard !flyingOff, index < queue.count else { return }
        let card = queue[index]
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        history.append(Step(box: store.box(deck: deck, card: card),
                            learnedAt: store.learnedStamp(deck: deck, card: card),
                            verdict: .skipped))
        withAnimation(.easeInOut(duration: 0.25)) { advance() }
    }

    private func undo() {
        guard let step = history.popLast(), index > 0 else { return }
        index -= 1
        flipped = false
        let card = queue[index]
        switch step.verdict {
        case .got: gotCount -= 1
        case .missed: missedCount -= 1
        case .skipped: break
        }
        if step.verdict != .skipped {
            store.restore(box: step.box, learnedAt: step.learnedAt, deck: deck, card: card)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func advance() {
        flipped = false
        index += 1
    }
}

struct CardFace: View {
    let card: Card
    let flipped: Bool

    private var text: String { flipped ? card.back : card.front }
    private var isLong: Bool { text.count > 300 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .shadow(radius: 8, y: 4)
            VStack(spacing: 12) {
                if !flipped, let video = card.video, let url = URL(string: video) {
                    LoopingVideoView(url: url)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if let image = flipped ? (card.backImage ?? card.image) : card.image {
                    RemoteImage(source: image)
                        .frame(maxHeight: text.count < 90 ? 360 : 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                // Exam-style cards (question + A/B/C/D) run long: smaller, left-aligned, scrollable
                if isLong {
                    ScrollView(.vertical) { cardText(text) }
                        .scrollIndicators(.hidden)
                } else {
                    cardText(text)
                }
                Text(flipped ? "answer · swipe → got it · ← missed" : "tap to flip · swipe to grade · hold to skip")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cardText(_ text: String) -> some View {
        Text(text)
            .font(text.count > 320 ? .subheadline.weight(.medium) : text.count > 120 ? .body.weight(.semibold) : .title2.weight(.semibold))
            .multilineTextAlignment(text.contains("\n") ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: text.contains("\n") ? .leading : .center)
            .padding(.horizontal)
    }
}

struct LoopingVideoView: View {
    let url: URL
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if looper == nil {
                    looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
                }
                player.isMuted = true
                player.play()
            }
            .onDisappear { player.pause() }
    }
}
