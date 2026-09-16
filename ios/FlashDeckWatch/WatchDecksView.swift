import SwiftUI

struct WatchDecksView: View {
    @EnvironmentObject var store: DeckStore

    private var inProgress: [Deck] { store.decks.filter { store.progress($0) < 1 } }
    private var completed: [Deck] { store.decks.filter { store.progress($0) >= 1 } }

    var body: some View {
        List {
            if !inProgress.isEmpty {
                Section("Continue learning") {
                    ForEach(inProgress) { deck in DeckRow(deck: deck) }
                }
            }
            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { deck in DeckRow(deck: deck) }
                }
            }
            if store.decks.isEmpty {
                Text(store.loading ? "Loading decks…" : "No decks yet")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Decks")
        .refreshable { await store.load() }
    }
}

struct DeckRow: View {
    @EnvironmentObject var store: DeckStore
    let deck: Deck

    var body: some View {
        NavigationLink(value: deck) {
            HStack(spacing: 10) {
                ProgressRing(value: store.progress(deck), size: 36, lineWidth: 3.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.name).font(.body.weight(.medium)).lineLimit(2)
                    Text("\(deck.cards.count) cards")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
