import Foundation
import WatchConnectivity

@MainActor
class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastReceivedBPM: Int?
    @Published var lastReceivedTimestamp: Date?

    private var session: WCSession?

    override private init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send Commands to Watch

    func sendStartWorkout() {
        guard let session = session, session.isReachable else {
            print("Watch not reachable")
            return
        }

        session.sendMessage(["command": "startWorkout"], replyHandler: nil) { error in
            print("Failed to send startWorkout: \(error)")
        }
    }

    func sendStopWorkout() {
        guard let session = session, session.isReachable else {
            print("Watch not reachable")
            return
        }

        session.sendMessage(["command": "stopWorkout"], replyHandler: nil) { error in
            print("Failed to send stopWorkout: \(error)")
        }
    }

    func sendThresholdUpdate(_ threshold: Int) {
        guard let session = session else {
            print("WCSession not available")
            return
        }

        // Use sendMessage if reachable, otherwise update application context
        if session.isReachable {
            session.sendMessage(["command": "updateThreshold", "threshold": threshold], replyHandler: nil) { error in
                print("Failed to send threshold update: \(error)")
                // Fallback to application context
                try? session.updateApplicationContext(["threshold": threshold])
            }
        } else {
            // Send via application context for delivery when watch becomes active
            try? session.updateApplicationContext(["threshold": threshold])
        }
    }

    // MARK: - Process Heart Rate

    private func processHeartRate(_ bpm: Int, timestamp: TimeInterval? = nil) async {
        lastReceivedBPM = bpm
        lastReceivedTimestamp = timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()

        // Forward to workout service
        await WorkoutService.shared.ingestHeartRate(bpm)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable

            // Check for any pending application context from watch
            let context = session.receivedApplicationContext
            if let bpm = context["heartRate"] as? Int {
                let timestamp = context["timestamp"] as? TimeInterval
                await self.processHeartRate(bpm, timestamp: timestamp)
            }
        }

        if let error = error {
            print("WCSession activation error: \(error)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = false
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = false
        }
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    // MARK: - Receive Messages (Real-time)

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            if let bpm = message["heartRate"] as? Int {
                await self.processHeartRate(bpm)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            if let bpm = message["heartRate"] as? Int {
                await self.processHeartRate(bpm)
                replyHandler(["received": true])
            } else {
                replyHandler(["received": false])
            }
        }
    }

    // MARK: - Receive Application Context (Fallback/Background)

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            // Handle heart rate from application context (fallback when sendMessage fails)
            if let bpm = applicationContext["heartRate"] as? Int {
                let timestamp = applicationContext["timestamp"] as? TimeInterval
                await self.processHeartRate(bpm, timestamp: timestamp)
            }
        }
    }
}
