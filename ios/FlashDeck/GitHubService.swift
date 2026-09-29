import Foundation
import Security

enum Keychain {
    private static let account = "github-token"
    private static let service = "com.djsly.flashdeck"

    static func saveToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct GitHubService {
    static let apiURL = URL(string: "https://api.github.com/repos/AssiamahS/flashdeck/contents/decks.json")!

    /// CI bakes a fine-grained token (Contents: read/write on AssiamahS/flashdeck only)
    /// into Info.plist from the FLASHDECK_GITHUB_TOKEN secret, so the phone never needs
    /// one typed in. A token pasted in Settings still wins if present.
    static var bundledToken: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "FlashDeckGitHubToken") as? String
        return (value?.isEmpty == false && value?.hasPrefix("$(") == false) ? value : nil
    }

    static var token: String? {
        if let saved = Keychain.readToken(), !saved.isEmpty { return saved }
        #if os(macOS)
        if let cli = ghCLIToken { return cli }
        #endif
        return bundledToken
    }

    #if os(macOS)
    /// The Mac app isn't sandboxed, so it borrows the GitHub CLI login already on this Mac
    /// (`gh auth token`). Nothing is baked into the public download.
    static let ghCLIToken: String? = {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            do { try process.run() } catch { continue }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0, !value.isEmpty { return value }
        }
        return nil
    }()
    #endif

    struct ContentsResponse: Decodable {
        let sha: String
        let content: String
    }

    enum GitHubError: LocalizedError {
        case noToken
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                #if os(macOS)
                return "No GitHub access on this Mac. Run `gh auth login` in Terminal once, or paste a token in Settings."
                #else
                return "No GitHub access on this iPhone yet. Paste a GitHub token (flashdeck repo, Contents read/write) in Settings."
                #endif
            case .http(let code, let body): return "GitHub \(code): \(body)"
            }
        }
    }

    static func fetch() async throws -> (file: DeckFile, sha: String) {
        guard let token else { throw GitHubError.noToken }
        var request = URLRequest(url: apiURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw GitHubError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let contents = try JSONDecoder().decode(ContentsResponse.self, from: data)
        guard let raw = Data(base64Encoded: contents.content.replacingOccurrences(of: "\n", with: "")) else {
            throw GitHubError.http(0, "undecodable file content")
        }
        let file = try JSONDecoder().decode(DeckFile.self, from: raw)
        return (file, contents.sha)
    }

    static func commit(_ file: DeckFile, sha: String, message: String) async throws {
        guard let token else { throw GitHubError.noToken }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(file)
        let body: [String: Any] = [
            "message": message,
            "content": data.base64EncodedString(),
            "sha": sha,
            "branch": "main",
        ]
        var request = URLRequest(url: apiURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (respData, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 201 else {
            throw GitHubError.http(code, String(data: respData, encoding: .utf8) ?? "")
        }
    }
}
