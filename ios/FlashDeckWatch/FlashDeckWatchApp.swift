import SwiftUI

@main
struct FlashDeckWatchApp: App {
    @StateObject private var store = DeckStore()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(store)
        }
    }
}

enum WatchTheme {
    static let accent = Color(red: 0.98, green: 0.72, blue: 0.24)
    static let card = Color.white.opacity(0.10)
}

/// Percent ring used on the deck list and the session summary.
struct ProgressRing: View {
    let value: Double
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4
    var tint: Color = .green
    var showLabel = true

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.01, min(value, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showLabel {
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }
}
