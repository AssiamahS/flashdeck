import SwiftUI

@main
struct FlashDeckApp: App {
    @StateObject private var store = DeckStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
