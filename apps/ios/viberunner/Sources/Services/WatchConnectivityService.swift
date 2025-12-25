import Foundation
import HealthKit
import WatchConnectivity

@MainActor
class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isReachable = false
    @Published var isWatchAppInstalled = false
    @Published var lastReceivedBPM: Int?
    @Published var lastReceivedTimestamp: Date?
    @Published var isMirroringActive = false

    private var session: WCSession?

    // HealthKit for workout session mirroring (receives HR even when watch screen dims)
    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?

    override private init() {
        super.init()
        setupSession()
        setupWorkoutMirroring()
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

    // MARK: - HKWorkoutSession Mirroring

    /// Set up handler to receive mirrored workout sessions from watch.
    /// This enables real-time HR delivery even when watch screen is dimmed.
    private func setupWorkoutMirroring() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            Task { @MainActor in
                guard let self = self else { return }
                print("[Mirroring] Received mirrored workout session from watch")
                self.mirroredSession = mirroredSession
                mirroredSession.delegate = self
                self.isMirroringActive = true
            }
        }
    }

    /// Request HealthKit authorization to enable workout session mirroring.
    /// Call this on app launch to ensure we can receive mirrored sessions.
    func requestHealthKitAuthorization() {
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            if let error = error {
                print("[Mirroring] HealthKit authorization error: \(error)")
            } else if success {
                print("[Mirroring] HealthKit authorization granted")
            }
        }
    }

    // MARK: - Send Commands to Watch

    /// Notify watch that phone has started a workout (for UI indicator)
    func sendWorkoutStarted() {
        guard let session = session else {
            print("WCSession not available")
            return
        }

        if session.isReachable {
            session.sendMessage(["command": "workoutStarted"], replyHandler: nil) { error in
                print("Failed to send workoutStarted: \(error)")
                // Fallback to application context
                try? session.updateApplicationContext(["workoutActive": true])
            }
        } else {
            // Send via application context for delivery when watch becomes active
            try? session.updateApplicationContext(["workoutActive": true])
        }
    }

    /// Notify watch that phone has stopped the workout
    func sendWorkoutStopped() {
        guard let session = session else {
            print("WCSession not available")
            return
        }

        if session.isReachable {
            session.sendMessage(["command": "workoutStopped"], replyHandler: nil) { error in
                print("Failed to send workoutStopped: \(error)")
                // Fallback to application context
                try? session.updateApplicationContext(["workoutActive": false])
            }
        } else {
            // Send via application context for delivery when watch becomes active
            try? session.updateApplicationContext(["workoutActive": false])
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

    /// Attempt to wake the watch app and prompt it to start HR monitoring
    /// Note: WatchConnectivity can't force-launch the watch app, but we can:
    /// 1. Send a message if reachable (watch app is open)
    /// 2. Send application context that will be delivered when watch app opens
    func requestWatchAppLaunch() {
        guard let session = session else {
            print("WCSession not available")
            return
        }

        guard session.isWatchAppInstalled else {
            print("Watch app not installed")
            return
        }

        // If already reachable, watch app is open - just ping it
        if session.isReachable {
            session.sendMessage(["command": "ping"], replyHandler: { response in
                print("Watch app responded: \(response)")
            }) { error in
                print("Watch ping failed: \(error)")
            }
        } else {
            // Watch app is not open - send context that will be received when user opens it
            // The watch app will auto-start HR monitoring when it opens
            try? session.updateApplicationContext(["requestedLaunch": Date().timeIntervalSince1970])
            print("Watch app not reachable - user needs to open watch app manually")
        }
    }

    // MARK: - Process Heart Rate

    private func processHeartRate(_ bpm: Int, timestamp: TimeInterval? = nil) async {
        lastReceivedBPM = bpm
        lastReceivedTimestamp = timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()

        // Forward to workout service - this updates display always, sends to API only during active workout
        await WorkoutService.shared.updateHeartRate(bpm)
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

    // MARK: - Receive User Info (Background transfer - queued delivery)

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            // Handle heart rate from transferUserInfo (used when watch screen dims)
            // Unlike applicationContext, transferUserInfo queues all messages for guaranteed delivery
            if let bpm = userInfo["heartRate"] as? Int {
                let timestamp = userInfo["timestamp"] as? TimeInterval
                await self.processHeartRate(bpm, timestamp: timestamp)
            }
        }
    }

    // MARK: - Receive Application Context (Legacy fallback)

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            // Handle heart rate from application context (legacy fallback)
            if let bpm = applicationContext["heartRate"] as? Int {
                let timestamp = applicationContext["timestamp"] as? TimeInterval
                await self.processHeartRate(bpm, timestamp: timestamp)
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate (Mirroring)

extension WatchConnectivityService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .ended, .stopped:
                print("[Mirroring] Session ended")
                self.mirroredSession = nil
                self.isMirroringActive = false
            case .running:
                print("[Mirroring] Session running")
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            print("[Mirroring] Session error: \(error)")
            self.isMirroringActive = false
        }
    }

    /// Receive HR data from watch via HKWorkoutSession mirroring.
    /// This works even when the watch screen is dimmed, unlike WatchConnectivity.
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor in
            for payload in data {
                do {
                    guard let dict = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                        continue
                    }

                    if let bpm = dict["heartRate"] as? Int {
                        let timestamp = dict["timestamp"] as? TimeInterval
                        print("[Mirroring] Received HR: \(bpm)")
                        await self.processHeartRate(bpm, timestamp: timestamp)
                    }
                } catch {
                    print("[Mirroring] Failed to decode HR data: \(error)")
                }
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor in
            print("[Mirroring] Disconnected from watch: \(error?.localizedDescription ?? "no error")")
            self.isMirroringActive = false
        }
    }
}
