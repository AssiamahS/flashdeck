import SwiftUI

@main
struct FlashDeckApp: App {
    @StateObject private var store = DeckStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                #if os(iOS)
                .updateCheck(site: "https://assiamahs.github.io/flashdeck")
                #endif
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 860)
        #endif
    }
}
