import AVFoundation
import Foundation
import MediaPlayer

/// Hands-free audio quiz: reads a card front, pauses so you can answer out loud,
/// then speaks the answer and moves on — card after card until stopped.
/// Runs as a background audio session, so it keeps going over CarPlay with the
/// phone locked. Car controls map: pause/play, next = skip card, previous = repeat.
@MainActor
final class VoiceQuizEngine: NSObject {
    static let shared = VoiceQuizEngine()

    private enum Phase { case question, answer }

    private let synth = AVSpeechSynthesizer()
    private var deck: Deck?
    private var queue: [Card] = []
    private var index = 0
    private var phase: Phase = .question
    private var gapTask: Task<Void, Never>?
    private(set) var isRunning = false
    private var paused = false

    /// Seconds of silence after the question before the answer is spoken.
    var answerGap: Double = 4.0

    private override init() {
        super.init()
        synth.delegate = self
        configureRemoteCommands()
    }

    func start(deck: Deck) throws {
        stopSpeech()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)

        self.deck = deck
        queue = Self.leitnerOrder(deck)
        index = 0
        isRunning = true
        paused = false
        speakQuestion()
    }

    func stop() {
        stopSpeech()
        isRunning = false
        deck = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Speech loop

    private func speakQuestion() {
        guard isRunning, let card = currentCard else { return }
        phase = .question
        updateNowPlaying()
        speak(card.front)
    }

    private func speakAnswer() {
        guard isRunning, let card = currentCard else { return }
        phase = .answer
        speak("The answer is: \(card.back)")
    }

    private func advance() {
        guard isRunning else { return }
        index += 1
        if index >= queue.count {
            // Wrap around, re-sorted so struggling cards come back first.
            if let deck { queue = Self.leitnerOrder(deck) }
            index = 0
        }
        speakQuestion()
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    private func utteranceFinished() {
        guard isRunning, !paused else { return }
        let delay = phase == .question ? answerGap : 1.5
        gapTask?.cancel()
        gapTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .question {
                self.speakAnswer()
            } else {
                self.advance()
            }
        }
    }

    private var currentCard: Card? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// Lowest Leitner box first (same "leitner" UserDefaults dict the app UI uses),
    /// shuffled within each box so runs aren't identical.
    private static func leitnerOrder(_ deck: Deck) -> [Card] {
        let boxes = UserDefaults.standard.dictionary(forKey: "leitner") as? [String: Int] ?? [:]
        return deck.cards
            .shuffled()
            .sorted { (boxes["\(deck.id)|\($0.front)"] ?? 1) < (boxes["\(deck.id)|\($1.front)"] ?? 1) }
    }

    // MARK: - Car / lock-screen controls

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.paused ? self.resume() : self.pause()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.repeatCard() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
    }

    private func pause() {
        paused = true
        gapTask?.cancel()
        synth.stopSpeaking(at: .immediate)
        updateNowPlaying()
    }

    private func resume() {
        guard isRunning else { return }
        paused = false
        // Re-speak the current phase from the top so nothing is lost mid-word.
        phase == .question ? speakQuestion() : speakAnswer()
    }

    private func skip() {
        guard isRunning else { return }
        paused = false
        gapTask?.cancel()
        synth.stopSpeaking(at: .immediate)
        advance()
    }

    private func repeatCard() {
        guard isRunning else { return }
        paused = false
        gapTask?.cancel()
        synth.stopSpeaking(at: .immediate)
        speakQuestion()
    }

    private func stopSpeech() {
        gapTask?.cancel()
        synth.stopSpeaking(at: .immediate)
    }

    private func updateNowPlaying() {
        guard let deck else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Card \(index + 1) of \(queue.count)",
            MPMediaItemPropertyArtist: deck.name,
            MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0,
        ]
    }
}

extension VoiceQuizEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceFinished() }
    }
}
