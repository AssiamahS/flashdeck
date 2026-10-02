import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var hasToken = Keychain.readToken() != nil
    @ObservedObject private var speaker = CardSpeaker.shared

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (build \(build))"
    }()

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
                    #if os(macOS)
                    if GitHubService.ghCLIToken != nil {
                        Label("Using this Mac's GitHub CLI login", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    #endif
                    SecureField("Fine-grained PAT", text: $token)
                        .noAutocapitalization()
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
                    Text("Editing and importing decks commits straight to the flashdeck repo, so changes go live on the Echo Show, the watch and the Mac too. The Mac app uses its GitHub CLI login automatically; on the iPhone, paste a token here once. Studying works without one.")
                        .font(.footnote)
                }
                Section {
                    LabeledContent("Version", value: Self.appVersion)
                }
            }
            .platformFormStyle()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
