import SwiftUI

struct EditorView: View {
    @EnvironmentObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var deckId = ""
    @State private var front = ""
    @State private var back = ""
    @State private var imageURL = ""
    @State private var newDeckName = ""
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    Text("Add Card").tag(0)
                    Text("New Deck").tag(1)
                }
                .pickerStyle(.segmented)
                if mode == 0 {
                    Picker("Deck", selection: $deckId) {
                        ForEach(store.decks) { deck in
                            Text(deck.name).tag(deck.id)
                        }
                    }
                    TextField("Front", text: $front, axis: .vertical)
                    TextField("Back", text: $back, axis: .vertical)
                    TextField("Image URL (optional)", text: $imageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    TextField("Deck name", text: $newDeckName)
                }
                if let status {
                    Text(status).font(.footnote)
                }
                Button(busy ? "Saving…" : "Save to GitHub") {
                    Task { await save() }
                }
                .disabled(busy || !valid)
            }
            .navigationTitle("Edit Decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if deckId.isEmpty { deckId = store.decks.first?.id ?? "" }
            }
        }
    }

    private var valid: Bool {
        if mode == 0 {
            return !front.isEmpty && !back.isEmpty && !deckId.isEmpty
        }
        return !newDeckName.isEmpty
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            var (file, sha) = try await GitHubService.fetch()
            if mode == 0 {
                guard let i = file.decks.firstIndex(where: { $0.id == deckId }) else {
                    status = "Deck \(deckId) not found in decks.json"
                    return
                }
                var card = Card(front: front, back: back, image: nil, video: nil)
                if !imageURL.isEmpty { card.image = imageURL }
                file.decks[i].cards.append(card)
                try await GitHubService.commit(file, sha: sha, message: "feat: add card to \(deckId) from phone")
                front = ""
                back = ""
                imageURL = ""
            } else {
                let id = newDeckName.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                file.decks.append(Deck(id: id, name: newDeckName, cards: []))
                try await GitHubService.commit(file, sha: sha, message: "feat: new deck \(id) from phone")
                newDeckName = ""
            }
            status = "Saved — live on your Echo Show in about a minute"
            await store.load()
        } catch {
            status = error.localizedDescription
        }
    }
}
