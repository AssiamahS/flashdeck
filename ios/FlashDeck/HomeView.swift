import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: DeckStore
    @State private var showSettings = false
    @State private var showEditor = false
    @State private var showImport = false
    @State private var quizDeck: Deck?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(store.decks) { deck in
                        NavigationLink(value: deck) {
                            DeckTile(deck: deck)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if QuizBuilder.canQuiz(deck) {
                                Button("Practice Test", systemImage: "list.bullet.clipboard") {
                                    quizDeck = deck
                                }
                            }
                        }
                    }
                }
                .padding()
                if let error = store.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Flash Deck")
            .navigationDestination(for: Deck.self) { deck in
                StudyView(deck: deck)
            }
            .navigationDestination(item: $quizDeck) { deck in
                QuizView(deck: deck)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("importButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showEditor) { EditorView() }
            .sheet(isPresented: $showImport) { ImportView() }
            .overlay {
                if store.loading && store.decks.isEmpty { ProgressView() }
            }
        }
    }
}

struct DeckTile: View {
    @EnvironmentObject var store: DeckStore
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.blue)
            Text(deck.name)
                .font(.headline)
                .lineLimit(2)
            Text("\(deck.cards.count) cards · \(store.masteredCount(deck)) mastered")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
