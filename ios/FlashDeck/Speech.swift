import AVFoundation
import Foundation

/// Reads the visible side of a card out loud. One shared synthesizer, so flipping
/// or moving on cuts the current sentence instead of stacking utterances.
/// The mute toggle persists across launches (defaults to on).
@MainActor
final class CardSpeaker: NSObject, ObservableObject {
    static let shared = CardSpeaker()
    static let enabledKey = "speakCards"

    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synth.delegate = self
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { stop() }
        }
    }

    func speak(_ text: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: Self.spoken(text))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speaking = true
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    /// Leaving the study screen: give the audio session back unless the voice quiz owns it.
    func release() {
        stop()
        guard !VoiceQuizEngine.shared.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Same cleanup the Echo skill does before speaking: each line of an exam card
    /// ("A. ...", "B. ...") becomes a short pause, whitespace collapses, and a
    /// trailing period is dropped so it isn't read as "dot".
    static func spoken(_ text: String) -> String {
        var out = text.split(separator: "\n")
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        while out.hasSuffix(".") { out.removeLast() }
        return out
    }
}

extension CardSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}
