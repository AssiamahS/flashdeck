import SwiftUI
import AVKit

struct StudyView: View {
    @EnvironmentObject var store: DeckStore
    let deck: Deck
    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var gotCount = 0
    @State private var missedCount = 0

    var body: some View {
        VStack(spacing: 16) {
            if index < queue.count {
                let card = queue[index]
                Text("\(index + 1) / \(queue.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                CardFace(card: card, flipped: flipped)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35)) { flipped.toggle() }
                    }
                if flipped {
                    HStack(spacing: 12) {
                        Button {
                            grade(got: false)
                        } label: {
                            Label("Missed it", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        Button {
                            grade(got: true)
                        } label: {
                            Label("Got it", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } else {
                    Button("Flip") {
                        withAnimation(.spring(duration: 0.35)) { flipped = true }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Skip") { advance() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
        .onAppear { if queue.isEmpty { start() } }
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
    }

    private func grade(got: Bool) {
        let card = queue[index]
        let current = store.box(deck: deck, card: card)
        store.setBox(got ? current + 1 : 1, deck: deck, card: card)
        if got { gotCount += 1 } else { missedCount += 1 }
        advance()
    }

    private func advance() {
        flipped = false
        index += 1
    }
}

struct CardFace: View {
    let card: Card
    let flipped: Bool

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
                } else if !flipped, let image = card.image, let url = URL(string: image) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(flipped ? card.back : card.front)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text(flipped ? "answer" : "tap to flip")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, minHeight: 340)
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
