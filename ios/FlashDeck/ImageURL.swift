import Foundation

/// Turns whatever gets pasted into the image field — a Google Images result, a
/// Wikipedia file page, a Dropbox share link, an SVG, a link full of utm_ junk —
/// into a URL an image view can actually load. Runs at save time (so decks.json
/// stays clean for the Echo Show) and again at display time for older cards.
enum ImageURL {
    private static let trackingParams: Set<String> = ["fbclid", "gclid", "igshid", "mc_cid", "mc_eid"]

    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text), let host = comps.host?.lowercased() else { return text }
        let path = comps.path

        // Google Images result page: the real picture is the imgurl parameter.
        if host.hasSuffix("google.com"), path.hasPrefix("/imgres"),
           let inner = comps.queryItems?.first(where: { $0.name == "imgurl" })?.value {
            return normalize(inner)
        }

        // Wikipedia / Commons "File:" page → the rendered file (SVGs come back as PNG).
        if host.hasSuffix("wikipedia.org") || host.hasSuffix("wikimedia.org"),
           let range = path.range(of: "/wiki/File:") {
            let name = String(path[range.upperBound...])
            return "https://commons.wikimedia.org/wiki/Special:FilePath/\(name)?width=1280"
        }

        // Direct SVG on upload.wikimedia.org → the PNG thumbnail they already render.
        if host == "upload.wikimedia.org", path.lowercased().hasSuffix(".svg"), !path.contains("/thumb/") {
            var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            // ["", "wikipedia", "commons", "6", "65", "Flag.svg"]
            if parts.count >= 6, let file = parts.last {
                parts.insert("thumb", at: 3)
                parts.append("1280px-\(file).png")
                comps.path = parts.joined(separator: "/")
                comps.queryItems = nil
                return comps.string ?? text
            }
        }

        // Dropbox share links → the raw file.
        if host.hasSuffix("dropbox.com") {
            comps.queryItems = [URLQueryItem(name: "raw", value: "1")]
            return comps.string ?? text
        }

        // Google Drive "view" links → direct download.
        if host == "drive.google.com" {
            let parts = path.split(separator: "/").map(String.init)
            if parts.count >= 3, parts[0] == "file", parts[1] == "d" {
                return "https://drive.google.com/uc?export=view&id=\(parts[2])"
            }
        }

        // Imgur page → direct image (imgur serves the right type regardless of extension).
        if host == "imgur.com", !path.hasPrefix("/a/"), !path.hasPrefix("/gallery/") {
            let id = (path as NSString).lastPathComponent
            if !id.isEmpty, !id.contains(".") { return "https://i.imgur.com/\(id).png" }
        }

        // Giphy page → the gif itself.
        if host.hasSuffix("giphy.com"), path.hasPrefix("/gifs/") {
            let id = path.split(separator: "-").last.map(String.init) ?? ""
            if !id.isEmpty, !id.contains("/") { return "https://media.giphy.com/media/\(id)/giphy.gif" }
        }

        // Tracking junk off the query string.
        if let items = comps.queryItems {
            let kept = items.filter { !$0.name.hasPrefix("utm_") && !trackingParams.contains($0.name) }
            comps.queryItems = kept.isEmpty ? nil : kept
        }

        // Any other SVG: iOS can't decode it, so ask wsrv.nl for a PNG render.
        if comps.path.lowercased().hasSuffix(".svg"), let url = comps.string {
            var proxy = URLComponents(string: "https://wsrv.nl/")!
            proxy.queryItems = [
                URLQueryItem(name: "url", value: url),
                URLQueryItem(name: "output", value: "png"),
                URLQueryItem(name: "w", value: "1280"),
            ]
            return proxy.string ?? url
        }

        return comps.string ?? text
    }
}
