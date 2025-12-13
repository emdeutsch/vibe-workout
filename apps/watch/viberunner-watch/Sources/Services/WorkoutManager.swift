import Foundation
import HealthKit
import WatchKit
import ClockKit

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    // Published state
    @Published var isWorkoutActive = false
    @Published var isPreparing = false
    @Published var countdownSeconds: Int = 0
    @Published var currentHeartRate: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var threshold: Int = 100

    // HealthKit
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    // Timer for elapsed time
    private var timer: Timer?
    private var workoutStartDate: Date?

    // Countdown duration (Apple recommends 3 seconds for sensor warm-up)
    private let countdownDuration = 3

    // HR above threshold?
    var isHROk: Bool {
        currentHeartRate >= threshold
    }

    var elapsedTimeString: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    override private init() {
        super.init()
        requestAuthorization()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit authorization error: \(error)")
            }
            if success {
                print("HealthKit authorization granted")
            }
        }
    }

    // MARK: - Workout Control

    func startWorkout() {
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

            // Prepare the session first (warms up sensors)
            isPreparing = true
            workoutSession?.prepare()

            // Start countdown to allow sensors to initialize
            startCountdown()

        } catch {
            print("Failed to create workout session: \(error)")
            isPreparing = false
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownSeconds = countdownDuration

        // Countdown timer
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                self.countdownSeconds -= 1

                if self.countdownSeconds <= 0 {
                    timer.invalidate()
                    self.beginWorkoutActivity()
                }
            }
        }
    }

    private func beginWorkoutActivity() {
        isPreparing = false

        let startDate = Date()
        workoutSession?.startActivity(with: startDate)
        workoutBuilder?.beginCollection(withStart: startDate) { [weak self] success, error in
            if success {
                Task { @MainActor in
                    self?.isWorkoutActive = true
                    self?.workoutStartDate = startDate
                    self?.startTimer()
                }
            } else if let error = error {
                print("Failed to begin workout collection: \(error)")
            }
        }
    }

    func stopWorkout() {
        guard let session = workoutSession else { return }

        // First, stop the activity to allow final metrics to be collected
        // This is important - don't skip straight to end()
        session.stopActivity(with: Date())
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startDate = self.workoutStartDate else { return }
                self.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Cleanup

    private func finishWorkout(endDate: Date) {
        workoutBuilder?.endCollection(withEnd: endDate) { [weak self] success, error in
            if let error = error {
                print("Failed to end collection: \(error)")
            }

            self?.workoutBuilder?.finishWorkout { workout, error in
                if let error = error {
                    print("Failed to finish workout: \(error)")
                } else if let workout = workout {
                    print("Workout saved: \(workout)")
                }
            }
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
            case .prepared:
                // Session is prepared, countdown should be running
                print("Workout session prepared, sensors warming up")

            case .running:
                self.isWorkoutActive = true
                self.isPreparing = false

            case .stopped:
                // Activity stopped, now we can end the session
                // This state occurs after stopActivity() is called
                self.workoutSession?.end()

            case .ended:
                self.isWorkoutActive = false
                self.isPreparing = false
                self.currentHeartRate = 0
                self.elapsedTime = 0
                self.workoutStartDate = nil
                self.stopTimer()

                // Finish and save the workout
                self.finishWorkout(endDate: date)

            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
        Task { @MainActor in
            self.isWorkoutActive = false
            self.isPreparing = false
            self.stopTimer()
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
