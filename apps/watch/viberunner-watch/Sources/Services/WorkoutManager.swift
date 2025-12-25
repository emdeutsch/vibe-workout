import Foundation
import HealthKit
import WatchKit
import ClockKit

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    // Published state
    @Published var isMonitoring = false
    @Published var currentHeartRate: Int = 0
    @Published var threshold: Int = 100
    @Published var isMirroringActive = false

    // Phone workout state (controlled by iPhone app)
    @Published var isPhoneWorkoutActive = false

    // HealthKit
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    override private init() {
        super.init()
    }

    // MARK: - Authorization & Start Monitoring

    func requestAuthorizationIfNeeded() {
        // If already monitoring, nothing to do
        guard !isMonitoring else {
            print("Already monitoring HR, skipping")
            return
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType()
        ]

        print("Requesting HealthKit authorization (or confirming existing)...")

        // Always request authorization - it's a no-op if already granted
        // The callback always fires, even if already authorized
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            Task { @MainActor in
                if let error = error {
                    print("HealthKit authorization error: \(error)")
                    return
                }

                if success {
                    print("HealthKit authorization confirmed, starting monitoring...")
                    self?.startMonitoring()
                } else {
                    print("HealthKit authorization denied")
                }
            }
        }
    }

    // MARK: - Auto-Start HR Monitoring

    /// Call this when the app becomes active to start HR monitoring
    func startMonitoring() {
        // Don't start if already monitoring
        guard !isMonitoring else {
            print("Already monitoring, skipping startMonitoring()")
            return
        }

        // Clean up any stale session
        if workoutSession != nil {
            print("Cleaning up stale workout session...")
            workoutSession = nil
            workoutBuilder = nil
        }

        print("Creating new workout session for HR monitoring...")

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .unknown

        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()

            workoutSession?.delegate = self
            workoutBuilder?.delegate = self

            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            // Start the session immediately (no countdown needed)
            let startDate = Date()
            print("Starting workout activity...")
            workoutSession?.startActivity(with: startDate)

            print("Beginning HR collection...")
            workoutBuilder?.beginCollection(withStart: startDate) { [weak self] success, error in
                Task { @MainActor in
                    if success {
                        self?.isMonitoring = true
                        print("✅ HR monitoring started successfully!")

                        // Start mirroring to companion device (iPhone)
                        // This enables real-time HR delivery even when watch screen dims
                        self?.startMirroringToPhone()
                    } else if let error = error {
                        print("❌ Failed to begin HR monitoring: \(error)")
                        // Clean up on failure
                        self?.workoutSession = nil
                        self?.workoutBuilder = nil
                    }
                }
            }

        } catch {
            print("❌ Failed to create workout session: \(error)")
            workoutSession = nil
            workoutBuilder = nil
        }
    }

    /// Stop monitoring (called when app goes to background or is closed)
    func stopMonitoring() {
        guard let session = workoutSession else { return }

        session.stopActivity(with: Date())
    }

    // MARK: - Phone Workout State

    /// Called when phone starts a workout with repos
    func phoneWorkoutStarted() {
        isPhoneWorkoutActive = true
    }

    /// Called when phone stops the workout
    func phoneWorkoutStopped() {
        isPhoneWorkoutActive = false
    }

    // MARK: - Cleanup

    private func finishWorkout(endDate: Date) {
        // We don't save the workout to HealthKit since this is just for HR monitoring
        // The user didn't explicitly start a "workout" - we're just reading HR
        isMirroringActive = false

        workoutBuilder?.endCollection(withEnd: endDate) { [weak self] _, _ in
            // Discard the workout (don't save to Health app)
            self?.workoutBuilder?.discardWorkout()

            Task { @MainActor in
                self?.workoutSession = nil
                self?.workoutBuilder = nil
            }
        }
    }

    // MARK: - HKWorkoutSession Mirroring

    /// Start mirroring the workout session to iPhone.
    /// This enables real-time HR delivery even when watch screen dims.
    private func startMirroringToPhone() {
        guard let session = workoutSession else {
            print("[Mirroring] No workout session to mirror")
            return
        }

        Task {
            do {
                try await session.startMirroringToCompanionDevice()
                await MainActor.run {
                    self.isMirroringActive = true
                    print("[Mirroring] Started mirroring to iPhone")
                }
            } catch {
                print("[Mirroring] Failed to start mirroring: \(error)")
                // Mirroring failed, but HR monitoring still works via WatchConnectivity fallback
            }
        }
    }

    /// Send HR to iPhone via HKWorkoutSession mirroring.
    /// This works even when watch screen is dimmed, unlike WatchConnectivity.
    func sendHeartRateViaMirroring(_ bpm: Int) {
        guard let session = workoutSession, isMirroringActive else {
            return
        }

        let payload: [String: Any] = [
            "heartRate": bpm,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            Task {
                do {
                    try await session.sendToRemoteWorkoutSession(data: data)
                } catch {
                    print("[Mirroring] Failed to send HR: \(error)")
                }
            }
        } catch {
            print("[Mirroring] Failed to encode HR data: \(error)")
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.isMonitoring = true
                print("HR monitoring session running")

            case .stopped:
                // Session stopped, end it
                self.workoutSession?.end()

            case .ended:
                self.isMonitoring = false
                self.currentHeartRate = 0
                print("HR monitoring session ended")

                // Cleanup
                self.finishWorkout(endDate: date)

            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
        Task { @MainActor in
            self.isMonitoring = false
            self.isMirroringActive = false
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor in
            print("[Mirroring] Disconnected from iPhone: \(error?.localizedDescription ?? "no error")")
            self.isMirroringActive = false
            // Note: HR data will continue via WatchConnectivity fallback
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  quantityType == HKObjectType.quantityType(forIdentifier: .heartRate) else {
                continue
            }

            let statistics = workoutBuilder.statistics(for: quantityType)
            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

            if let mostRecent = statistics?.mostRecentQuantity() {
                let heartRate = Int(mostRecent.doubleValue(for: heartRateUnit))

                Task { @MainActor in
                    self.currentHeartRate = heartRate

                    // Primary: Send via HKWorkoutSession mirroring (works when screen dims)
                    if self.isMirroringActive {
                        self.sendHeartRateViaMirroring(heartRate)
                    }
                    // Fallback: Send via WatchConnectivity (for backwards compatibility)
                    PhoneConnectivityService.shared.sendHeartRate(heartRate)

                    // Reload watch face complications with updated HR
                    ComplicationController.reloadComplications()
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}
