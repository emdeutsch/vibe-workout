import Foundation
import WatchConnectivity

@MainActor
class PhoneConnectivityService: NSObject, ObservableObject {
    static let shared = PhoneConnectivityService()

    @Published var isReachable = false
    @Published var currentThreshold: Int?

    private var session: WCSession?

    // Throttling: minimum interval between HR messages (in seconds)
    // HR updates more frequently than needed for our 15-second TTL
    private let minimumSendInterval: TimeInterval = 2.0
    private var lastSendTime: Date?
    private var pendingHeartRate: Int?
    private var throttleTimer: Timer?

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

    // MARK: - Send Heart Rate to Phone (Throttled)

    func sendHeartRate(_ bpm: Int) {
        let now = Date()

        // Check if we should send immediately or throttle
        if let lastSend = lastSendTime {
            let elapsed = now.timeIntervalSince(lastSend)

            if elapsed < minimumSendInterval {
                // Throttle: store the value and send later
                pendingHeartRate = bpm
                scheduleThrottledSend(delay: minimumSendInterval - elapsed)
                return
            }
        }

        // Send immediately
        doSendHeartRate(bpm)
    }

    private func scheduleThrottledSend(delay: TimeInterval) {
        // Cancel any existing timer
        throttleTimer?.invalidate()

        // Schedule a new send after the delay
        throttleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let bpm = self.pendingHeartRate else { return }
                self.pendingHeartRate = nil
                self.doSendHeartRate(bpm)
            }
        }
    }

    private func doSendHeartRate(_ bpm: Int) {
        lastSendTime = Date()

        guard let session = session, session.isReachable else {
            // Fallback: send via application context when phone not reachable
            // This ensures data isn't lost when phone is in background
            try? session?.updateApplicationContext([
                "heartRate": bpm,
                "timestamp": Date().timeIntervalSince1970
            ])
            return
        }

        // Primary: send interactive message for real-time delivery
        session.sendMessage(["heartRate": bpm], replyHandler: { response in
            // Message delivered successfully
        }) { error in
            print("Failed to send heart rate: \(error)")

            // Fallback to application context on failure
            try? self.session?.updateApplicationContext([
                "heartRate": bpm,
                "timestamp": Date().timeIntervalSince1970
            ])
        }
    }

    // MARK: - Force Send (for critical updates)

    /// Send immediately without throttling (use sparingly)
    func sendHeartRateImmediate(_ bpm: Int) {
        throttleTimer?.invalidate()
        pendingHeartRate = nil
        doSendHeartRate(bpm)
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }

        if let error = error {
            print("WCSession activation error: \(error)")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // Receive messages from phone
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            handleMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            handleMessage(message)
            replyHandler(["received": true])
        }
    }

    @MainActor
    private func handleMessage(_ message: [String: Any]) {
        if let command = message["command"] as? String {
            switch command {
            case "startWorkout":
                WorkoutManager.shared.startWorkout()

            case "stopWorkout":
                WorkoutManager.shared.stopWorkout()

            case "updateThreshold":
                if let threshold = message["threshold"] as? Int {
                    currentThreshold = threshold
                }

            default:
                break
            }
        }
    }
}
