import Foundation
import SwiftUI
import Combine
import CoreLocation

/// Main application state
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties

    @Published var isOnboarded: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var claudeAppSelected: Bool = false
    @Published var githubConnected: Bool = false
    @Published var hasGatedRepos: Bool = false

    @Published var runState: RunState = .notRunning
    @Published var currentPace: Double? = nil // seconds per mile
    @Published var totalDistance: Double = 0 // meters
    @Published var runDuration: TimeInterval = 0

    /// User's pace threshold setting (seconds per mile)
    @Published var paceThresholdSeconds: Int = 600 // Default 10:00/mi

    /// Route coordinates for map display
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    /// Current user location for map centering
    @Published var currentLocation: CLLocationCoordinate2D?

    @Published var error: AppError? = nil

    // MARK: - Services

    let locationService = LocationService()
    let screenTimeService = ScreenTimeService()
    let apiService = APIService()
    let paceCalculator = PaceCalculator()
    let healthKitService = HealthKitService()
    let authService = AuthService.shared

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var runTimer: Timer?
    private var heartbeatTimer: Timer?
    private var runStartTime: Date?
    private var routeLocations: [CLLocation] = [] // For HealthKit route
    private var caloriesEstimate: Double = 0

    // MARK: - Initialization

    func initialize() async {
        // Load persisted state
        loadPersistedState()

        // Set up location updates
        setupLocationUpdates()

        // Set up auth state observation
        setupAuthObserver()

        // Check for existing Supabase session
        do {
            try await authService.checkSession()
            if authService.isAuthenticated {
                isAuthenticated = true
                await refreshUserState()
            }
        } catch {
            // No existing session, user needs to sign in
            print("No existing session: \(error)")
        }

        // Request HealthKit authorization
        if healthKitService.isAvailable {
            do {
                try await healthKitService.requestAuthorization()
            } catch {
                print("HealthKit authorization failed: \(error)")
            }
        }
    }

    private func setupAuthObserver() {
        authService.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                self?.isAuthenticated = isAuth
                if isAuth {
                    Task {
                        await self?.refreshUserState()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        isOnboarded = true
        UserDefaults.standard.set(true, forKey: "isOnboarded")
    }

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws {
        try await authService.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await authService.signUp(email: email, password: password)
    }

    func signInWithMagicLink(email: String) async throws {
        try await authService.signInWithMagicLink(email: email)
    }

    func signOut() async throws {
        try await authService.signOut()
        isAuthenticated = false
        githubConnected = false
        hasGatedRepos = false
    }

    func refreshUserState() async {
        do {
            let profile = try await apiService.getProfile()
            githubConnected = profile.githubConnected
            paceThresholdSeconds = profile.paceThresholdSeconds
            let repos = try await apiService.getGatedRepos()
            hasGatedRepos = !repos.isEmpty
        } catch {
            print("Failed to refresh user state: \(error)")
        }
    }

    // MARK: - Pace Threshold

    func updatePaceThreshold(seconds: Int) async throws {
        try await apiService.updatePaceThreshold(seconds: seconds)
        paceThresholdSeconds = seconds
    }

    // MARK: - Run Session

    func startRun() async {
        guard runState == .notRunning else { return }

        // Request location permission if needed
        await locationService.requestPermission()

        // Start location tracking
        locationService.startTracking()

        // Reset state
        paceCalculator.reset()
        totalDistance = 0
        runDuration = 0
        currentPace = nil
        routeCoordinates = []
        routeLocations = []
        caloriesEstimate = 0
        runStartTime = Date()

        // Initial state is locked (must prove pace)
        runState = .runningLocked

        // Block Claude immediately
        await screenTimeService.blockClaude()

        // Start HealthKit workout
        if healthKitService.isAvailable {
            do {
                try await healthKitService.startWorkout()
            } catch {
                print("Failed to start HealthKit workout: \(error)")
            }
        }

        // Notify backend
        do {
            try await apiService.startRun()
        } catch {
            print("Failed to notify backend of run start: \(error)")
        }

        // Start timers
        startRunTimer()
        startHeartbeatTimer()
    }

    func endRun() async {
        guard runState != .notRunning else { return }

        let endTime = Date()

        // Stop tracking
        locationService.stopTracking()
        stopRunTimer()
        stopHeartbeatTimer()

        // Unblock Claude
        await screenTimeService.unblockClaude()

        // Save to HealthKit
        var healthKitWorkoutId: String? = nil
        if healthKitService.isAvailable, let startTime = runStartTime {
            do {
                // Add final route data
                if !routeLocations.isEmpty {
                    try await healthKitService.addRouteData(locations: routeLocations)
                }

                // End and save workout
                let workout = try await healthKitService.endWorkout(
                    distanceMeters: totalDistance,
                    caloriesBurned: caloriesEstimate,
                    startDate: startTime,
                    endDate: endTime
                )
                healthKitWorkoutId = workout?.uuid.uuidString
            } catch {
                print("Failed to save HealthKit workout: \(error)")
            }
        }

        runState = .notRunning

        // Build route data for backend
        let route: [[String: Any]] = routeCoordinates.enumerated().map { index, coord in
            [
                "lat": coord.latitude,
                "lng": coord.longitude,
                "timestamp": Int((runStartTime?.timeIntervalSince1970 ?? 0) * 1000) + (index * 5000),
                "pace": currentPace ?? 0
            ]
        }

        // Notify backend with final stats
        do {
            try await apiService.endRun(
                distanceMeters: totalDistance,
                averagePaceSeconds: currentPace,
                caloriesBurned: caloriesEstimate,
                route: route,
                healthKitWorkoutId: healthKitWorkoutId
            )
        } catch {
            print("Failed to notify backend of run end: \(error)")
        }
    }

    // MARK: - Private Methods

    private func loadPersistedState() {
        isOnboarded = UserDefaults.standard.bool(forKey: "isOnboarded")
        claudeAppSelected = UserDefaults.standard.bool(forKey: "claudeAppSelected")
    }

    private func setupLocationUpdates() {
        locationService.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                await self?.handleLocationUpdate(location)
            }
        }
    }

    private func handleLocationUpdate(_ location: LocationSample) async {
        // Always update current location for map centering
        let coordinate = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        currentLocation = coordinate

        guard runState != .notRunning else { return }

        // Add to route for map display
        routeCoordinates.append(coordinate)

        // Add to HealthKit route
        let clLocation = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: location.accuracy,
            verticalAccuracy: 0,
            timestamp: Date(timeIntervalSince1970: location.timestamp / 1000)
        )
        routeLocations.append(clLocation)

        // Calculate pace
        if let pace = paceCalculator.addSample(location) {
            currentPace = pace
            totalDistance = paceCalculator.totalDistance

            // Estimate calories (rough: 100 cal per mile for 150lb person)
            let miles = totalDistance / 1609.344
            caloriesEstimate = miles * 100

            // Update run state based on pace
            await updateRunState(pace: pace)
        }
    }

    private func updateRunState(pace: Double) async {
        let threshold = Double(paceThresholdSeconds)
        let hysteresis: Double = 15 // 15 second buffer

        let previousState = runState

        // Hysteresis logic
        if runState == .runningLocked && pace < (threshold - hysteresis) {
            runState = .runningUnlocked
        } else if runState == .runningUnlocked && pace > (threshold + hysteresis) {
            runState = .runningLocked
        }

        // Handle state change
        if runState != previousState {
            if runState == .runningUnlocked {
                await screenTimeService.unblockClaude()
            } else if runState == .runningLocked {
                await screenTimeService.blockClaude()
            }
        }
    }

    private func startRunTimer() {
        runTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let startTime = self?.runStartTime {
                    self?.runDuration = Date().timeIntervalSince(startTime)
                }
            }
        }
    }

    private func stopRunTimer() {
        runTimer?.invalidate()
        runTimer = nil
    }

    private func startHeartbeatTimer() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendHeartbeat()
            }
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() async {
        guard runState != .notRunning else { return }

        // Build route data
        let route: [[String: Any]] = routeCoordinates.enumerated().map { index, coord in
            [
                "lat": coord.latitude,
                "lng": coord.longitude,
                "timestamp": Int((runStartTime?.timeIntervalSince1970 ?? 0) * 1000) + (index * 5000),
                "pace": currentPace ?? 0
            ]
        }

        do {
            let response = try await apiService.sendHeartbeat(
                runState: runState,
                pace: currentPace,
                distanceMeters: totalDistance,
                caloriesBurned: caloriesEstimate,
                route: route,
                location: locationService.lastLocation
            )

            // Update pace threshold if server returns a different value
            if response.paceThresholdSeconds != paceThresholdSeconds {
                paceThresholdSeconds = response.paceThresholdSeconds
            }
        } catch {
            print("Heartbeat failed: \(error)")
        }
    }
}

// MARK: - Types

enum RunState: String, Codable {
    case notRunning = "NOT_RUNNING"
    case runningUnlocked = "RUNNING_UNLOCKED"
    case runningLocked = "RUNNING_LOCKED"
}

enum AppError: Error, Identifiable {
    case network(String)
    case auth(String)
    case screenTime(String)
    case location(String)
    case healthKit(String)

    var id: String {
        switch self {
        case .network(let msg): return "network-\(msg)"
        case .auth(let msg): return "auth-\(msg)"
        case .screenTime(let msg): return "screenTime-\(msg)"
        case .location(let msg): return "location-\(msg)"
        case .healthKit(let msg): return "healthKit-\(msg)"
        }
    }

    var message: String {
        switch self {
        case .network(let msg): return msg
        case .auth(let msg): return msg
        case .screenTime(let msg): return msg
        case .location(let msg): return msg
        case .healthKit(let msg): return msg
        }
    }
}
