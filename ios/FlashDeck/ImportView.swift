import SwiftUI
import WebKit

/// Paste a flashcard-set link (Quizlet etc.), the page loads in a real WebKit view — so
/// sites that block plain HTTP fetches with a bot check still render — and the extractor
/// script reads the cards off the page. Save = new deck in decks.json, or new cards into a
/// deck with the same name.
@MainActor
final class ImportEngine: NSObject, ObservableObject {
    @Published var result: CardExtractor.Result?
    @Published var status = ""
    @Published var loading = false
    let web: WKWebView
    private var tries = 0
    private var generation = 0

    override init() {
        web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        web.navigationDelegate = self
    }

    func load(_ text: String) {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.contains("://") { string = "https://" + string }
        guard let url = URL(string: string), url.host != nil else {
            status = "That doesn't look like a link"
            return
        }
        generation += 1
        tries = 0
        result = nil
        loading = true
        status = "Loading…"
        web.load(URLRequest(url: url))
    }

    private func poll() {
        let gen = generation
        tries += 1
        web.evaluateJavaScript(CardExtractor.script) { [weak self] value, error in
            Task { @MainActor in self?.handle(value, error, gen: gen) }
        }
    }

    private func handle(_ value: Any?, _ error: Error?, gen: Int) {
        guard gen == generation else { return }
        if let text = value as? String,
           let data = text.data(using: .utf8),
           let found = try? JSONDecoder().decode(CardExtractor.Result.self, from: data) {
            if found.count > 0 {
                result = found
                loading = false
                status = "\(found.count) cards found"
                return
            }
            status = found.blocked
                ? "The site is checking for a real person — finish that in the page below"
                : "Looking for cards on the page…"
        } else if let error {
            status = error.localizedDescription
        }
        guard tries < 20 else {
            loading = false
            status = "No cards found on that page"
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            poll()
        }
    }
}

extension ImportEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.poll() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        Task { @MainActor in
            self.loading = false
            self.status = error.localizedDescription
        }
    }
}

struct ImportView: View {
    @EnvironmentObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = ImportEngine()
    @State private var link = ""
    @State private var deckName = ""
    @State private var busy = false
    @State private var saved: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Flashcard set link") {
                    TextField("https://quizlet.com/…", text: $link)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                        .urlKeyboard()
                        .onSubmit { engine.load(link) }
                    Button(engine.loading ? "Loading…" : "Fetch cards") { engine.load(link) }
                        .disabled(link.isEmpty || engine.loading)
                    if !engine.status.isEmpty {
                        Text(engine.status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    WebPane(web: engine.web)
                        .frame(height: engine.result == nil ? 320 : 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } header: {
                    Text("Page")
                } footer: {
                    Text("Loads like Safari, so sites that want a real browser still work. If it shows a press-and-hold check, do it right here.")
                }
                if let set = engine.result {
                    Section("\(set.cards.count) cards") {
                        TextField("Deck name", text: $deckName)
                        ForEach(Array(set.cards.prefix(6).enumerated()), id: \.offset) { _, card in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.front)
                                Text(card.back).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if set.cards.count > 6 {
                            Text("… and \(set.cards.count - 6) more").font(.caption).foregroundStyle(.secondary)
                        }
                        Button(busy ? "Saving…" : "Save as deck") { Task { await save(set.cards) } }
                            .disabled(busy || deckName.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let saved {
                            Text(saved).font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Import Cards")
            .inlineTitleBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: engine.result?.title) { _, title in
                if deckName.isEmpty, let title, !title.isEmpty { deckName = title }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 720)
        #endif
    }

    private func save(_ cards: [Card]) async {
        busy = true
        defer { busy = false }
        let name = deckName.trimmingCharacters(in: .whitespaces)
        let id = Deck.slug(name)
        let host = URL(string: link)?.host ?? "the web"
        do {
            var (file, sha) = try await GitHubService.fetch()
            if let i = file.decks.firstIndex(where: { $0.id == id }) {
                let existing = Set(file.decks[i].cards.map(\.front))
                let fresh = cards.filter { !existing.contains($0.front) }
                file.decks[i].cards += fresh
                try await GitHubService.commit(file, sha: sha, message: "feat: import \(fresh.count) cards into \(id) from \(host)")
                let skipped = cards.count - fresh.count
                saved = "Added \(fresh.count) new cards to \(file.decks[i].name)" + (skipped > 0 ? " (\(skipped) already there)" : "")
            } else {
                file.decks.append(Deck(id: id, name: name, cards: cards))
                try await GitHubService.commit(file, sha: sha, message: "feat: import deck \(id) (\(cards.count) cards) from \(host)")
                saved = "Saved \(cards.count) cards as \(name) — live on the Echo Show in about a minute"
            }
            await store.load()
        } catch {
            saved = error.localizedDescription
        }
    }
}

/// The engine owns the WKWebView; this just puts it on screen.
struct WebPane: View {
    let web: WKWebView
    var body: some View { WebPaneRepresentable(web: web) }
}

#if canImport(UIKit)
private struct WebPaneRepresentable: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#else
private struct WebPaneRepresentable: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#endif
