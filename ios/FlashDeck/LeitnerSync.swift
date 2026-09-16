import Foundation
import WatchConnectivity

/// Keeps Leitner boxes in step between the iPhone and the watch.
/// iPhone is the source of truth: it pushes the full snapshot as application
/// context on every change; the watch queues each grade as user info, which
/// WatchConnectivity delivers (launching the iPhone app in the background if
/// needed), and the phone answers with a fresh snapshot.
@MainActor
final class LeitnerSync: NSObject, WCSessionDelegate {
    /// Full snapshot from the phone (boxes, learnedAt).
    var onSnapshot: (([String: Int], [String: Double]) -> Void)?
    /// One grade from the watch (key, box, learnedAt).
    var onGrade: ((String, Int, Double?) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func didGrade(key: String, box: Int, learnedAt: Double?, boxes: [String: Int], learned: [String: Double]) {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(["leitner": boxes, "learnedAt": learned])
        #else
        var info: [String: Any] = ["key": key, "box": box]
        if let learnedAt { info["learnedAt"] = learnedAt }
        session.transferUserInfo(info)
        #endif
    }

    private func pushSnapshot() {
        #if os(iOS)
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let boxes = UserDefaults.standard.dictionary(forKey: "leitner") as? [String: Int] ?? [:]
        let learned = UserDefaults.standard.dictionary(forKey: "learnedAt") as? [String: Double] ?? [:]
        try? session.updateApplicationContext(["leitner": boxes, "learnedAt": learned])
        #endif
    }

    // MARK: WCSessionDelegate (called off the main actor)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        guard state == .activated else { return }
        Task { @MainActor in self.pushSnapshot() }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let boxes = context["leitner"] as? [String: Int] else { return }
        let learned = context["learnedAt"] as? [String: Double] ?? [:]
        Task { @MainActor in self.onSnapshot?(boxes, learned) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let key = userInfo["key"] as? String, let box = userInfo["box"] as? Int else { return }
        let learnedAt = userInfo["learnedAt"] as? Double
        Task { @MainActor in
            self.onGrade?(key, box, learnedAt)
            self.pushSnapshot()
        }
    }
}
