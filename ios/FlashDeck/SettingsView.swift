import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var hasToken = Keychain.readToken() != nil
    @ObservedObject private var speaker = CardSpeaker.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Read cards aloud", isOn: Binding(
                        get: { speaker.enabled },
                        set: { speaker.enabled = $0 }
                    ))
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Speaks the question when a card appears and the answer when you flip. The speaker button on a card reads it on demand even when this is off.")
                }
                Section("GitHub token") {
                    if GitHubService.bundledToken != nil {
                        Label("Editor access is built into this build", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    SecureField("Fine-grained PAT", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save token") {
                        Keychain.saveToken(token)
                        token = ""
                        hasToken = true
                    }
                    .disabled(token.isEmpty)
                    if hasToken {
                        Label("Token saved in Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section {
                    Text("Editing decks commits straight to the flashdeck repo, so changes go live on the Echo Show and the watch too. TestFlight builds carry their own token; paste one here only to override it. Studying works without a token.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
