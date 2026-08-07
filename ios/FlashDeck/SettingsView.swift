import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var hasToken = Keychain.readToken() != nil

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub token") {
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
                    Text("Editing decks commits straight to the flashdeck repo, so changes go live on the Echo Show too. Create a fine-grained token on github.com scoped to AssiamahS/flashdeck with Contents read & write — it never leaves this phone's Keychain. Studying works without a token.")
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
