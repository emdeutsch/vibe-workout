import Foundation
import HealthKit
import CoreLocation

/// Service for integrating with HealthKit for workout tracking
class HealthKitService {
    private let healthStore = HKHealthStore()
    private var workoutBuilder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var currentWorkoutSession: HKWorkoutSession?

    /// Whether HealthKit is available on this device
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request HealthKit authorization
    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        // Types we want to read
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKSeriesType.workoutRoute(),
        ]

        // Types we want to write
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute(),
        ]

        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// Start recording a workout
    func startWorkout() async throws {
        guard isAvailable else {
            throw HealthKitError.notAvailable
        }

        // Create workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        // Create workout builder
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: Date())
        self.workoutBuilder = builder

        // Create route builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
    }

    /// Add location samples to the workout route
    func addRouteData(locations: [CLLocation]) async throws {
        guard let routeBuilder = routeBuilder else { return }
        try await routeBuilder.insertRouteData(locations)
    }

    /// Add a distance sample
    func addDistanceSample(meters: Double, start: Date, end: Date) async throws {
        guard let builder = workoutBuilder else { return }

        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: meters)
        let distanceSample = HKQuantitySample(
            type: distanceType,
            quantity: distanceQuantity,
            start: start,
            end: end
        )

        try await builder.add([distanceSample])
    }

    /// Add calories burned sample
    func addCaloriesSample(calories: Double, start: Date, end: Date) async throws {
        guard let builder = workoutBuilder else { return }

        let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let caloriesQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
        let caloriesSample = HKQuantitySample(
            type: caloriesType,
            quantity: caloriesQuantity,
            start: start,
            end: end
        )

        try await builder.add([caloriesSample])
    }

    /// End the workout and save to HealthKit
    func endWorkout(
        distanceMeters: Double,
        caloriesBurned: Double,
        startDate: Date,
        endDate: Date
    ) async throws -> HKWorkout? {
        guard let builder = workoutBuilder else {
            throw HealthKitError.noActiveWorkout
        }

        // End collection
        try await builder.endCollection(at: endDate)

        // Add final statistics
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
        let distanceSample = HKQuantitySample(
            type: distanceType,
            quantity: distanceQuantity,
            start: startDate,
            end: endDate
        )

        let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let caloriesQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: caloriesBurned)
        let caloriesSample = HKQuantitySample(
            type: caloriesType,
            quantity: caloriesQuantity,
            start: startDate,
            end: endDate
        )

        try await builder.add([distanceSample, caloriesSample])

        // Finish and save workout
        let workout = try await builder.finishWorkout()

        // Save route if we have one
        if let routeBuilder = routeBuilder, let workout = workout {
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }

        // Cleanup
        self.workoutBuilder = nil
        self.routeBuilder = nil

        return workout
    }

    /// Cancel the current workout without saving
    func cancelWorkout() async {
        if let builder = workoutBuilder {
            builder.discardWorkout()
        }
        self.workoutBuilder = nil
        self.routeBuilder = nil
    }

    /// Get recent running workouts
    func getRecentWorkouts(limit: Int = 20) async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()

        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - Errors

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case noActiveWorkout
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .noActiveWorkout:
            return "No active workout to save"
        case .authorizationDenied:
            return "HealthKit authorization denied"
        }
    }
}
