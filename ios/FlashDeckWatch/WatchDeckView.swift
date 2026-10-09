import SwiftUI

/// Deck screen: pick flashcards or a practice test.
struct WatchDeckView: View {
    @EnvironmentObject var store: DeckStore
    let deck: Deck

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ProgressRing(value: store.progress(deck), size: 56, lineWidth: 5)
                Text("\(deck.cards.count) cards")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                NavigationLink(value: deck) {
                    Label("Flashcards", systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                .foregroundStyle(.black)
                if QuizBuilder.canQuiz(deck) {
                    NavigationLink(value: WatchHomeView.Route.quiz(deck)) {
                        Label("Practice test", systemImage: "list.bullet.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
