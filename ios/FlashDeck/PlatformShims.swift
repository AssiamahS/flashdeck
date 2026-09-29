import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Mac target compiles the same views; these are the iPhone-only modifiers
/// and haptics, no-ops on macOS.
extension View {
    func inlineTitleBar() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    func noAutocapitalization() -> some View {
        #if os(iOS)
        return textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }

    func urlKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.URL)
        #else
        return self
        #endif
    }
}

enum Haptics {
    static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func verdict(success: Bool) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        #endif
    }
}
