import SwiftUI
import WatchKit

struct WatchStudyView: View {
    @EnvironmentObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    let deck: Deck
    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var flipped = false
    @State private var gotCount = 0
    @State private var missedCount = 0

    var body: some View {
        Group {
            if index < queue.count {
                lesson(queue[index])
            } else if !queue.isEmpty {
                summary
            } else {
                ProgressView()
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if queue.isEmpty { start() } }
    }

    private func lesson(_ card: Card) -> some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(index), total: Double(queue.count))
                .tint(WatchTheme.accent)
            WatchCardFace(card: card, flipped: flipped)
                .onTapGesture { flip() }
            HStack(spacing: 14) {
                if flipped {
                    Button { grade(got: false) } label: {
                        Image(systemName: "xmark").font(.body.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.red)
                    Button { grade(got: true) } label: {
                        Image(systemName: "checkmark").font(.body.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.green)
                } else {
                    Button("Flip") { flip() }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.accent)
                        .foregroundStyle(.black)
                }
            }
        }
    }

    private var summary: some View {
        let total = gotCount + missedCount
        let got = total == 0 ? 0 : Double(gotCount) / Double(total)
        return ScrollView {
            VStack(spacing: 8) {
                ProgressRing(value: got, size: 96, lineWidth: 8, tint: WatchTheme.accent, showLabel: false)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(Int((got * 100).rounded()))%")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("Got it").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                Text("\(Int((store.progress(deck) * 100).rounded()))% mastered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Study again") { start() }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.accent)
                    .foregroundStyle(.black)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func start() {
        // Leitner: lowest boxes (least known) come first, same as the phone and the Show
        queue = deck.cards.sorted {
            store.box(deck: deck, card: $0) < store.box(deck: deck, card: $1)
        }
        index = 0
        flipped = false
        gotCount = 0
        missedCount = 0
        store.lastDeckId = deck.id
    }

    private func flip() {
        withAnimation(.spring(duration: 0.3)) { flipped.toggle() }
        WKInterfaceDevice.current().play(.click)
    }

    private func grade(got: Bool) {
        store.grade(deck: deck, card: queue[index], got: got)
        if got { gotCount += 1 } else { missedCount += 1 }
        WKInterfaceDevice.current().play(got ? .success : .failure)
        flipped = false
        index += 1
    }
}

struct WatchCardFace: View {
    let card: Card
    let flipped: Bool

    private var text: String { flipped ? card.back : card.front }
    private var imageURL: URL? {
        let raw = flipped ? (card.backImage ?? card.image) : card.image
        return raw.flatMap(URL.init(string:))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let imageURL {
                    AsyncImage(url: imageURL) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: text.count < 40 ? 70 : 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(text)
                    .font(text.count > 200 ? .caption2 : text.count > 60 ? .footnote : .body.weight(.semibold))
                    .multilineTextAlignment(text.contains("\n") || text.count > 60 ? .leading : .center)
                    .frame(maxWidth: .infinity, alignment: text.contains("\n") || text.count > 60 ? .leading : .center)
                Text(flipped ? "answer" : "tap to flip")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 84)
        }
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxHeight: .infinity)
    }
}
