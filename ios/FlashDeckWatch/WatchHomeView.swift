import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject var store: DeckStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(store.learnedThisWeek())")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Cards learned\nthis week")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    if let deck = store.lastDeck {
                        NavigationLink(value: deck) {
                            Text("Continue learning")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.accent)
                        .foregroundStyle(.black)
                    } else {
                        NavigationLink(value: Route.decks) {
                            Text("Start learning")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.accent)
                        .foregroundStyle(.black)
                    }

                    NavigationLink(value: Route.decks) {
                        Text("Decks")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if store.decks.isEmpty, store.loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if store.decks.isEmpty, let error = store.errorMessage {
                        Text(error).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: Deck.self) { deck in WatchStudyView(deck: deck) }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .decks: WatchDecksView()
                }
            }
            .task { await store.load() }
        }
        .tint(WatchTheme.accent)
    }

    enum Route: Hashable {
        case decks
    }
}
