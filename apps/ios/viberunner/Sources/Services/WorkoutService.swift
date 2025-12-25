import Foundation

@MainActor
class WorkoutService: ObservableObject {
    static let shared = WorkoutService()

    @Published var isActive = false
    @Published var currentSessionId: String?
    @Published var currentBPM: Int = 0
    @Published var toolsUnlocked = false
    @Published var error: String?

    // Selected repos for current workout
    @Published var selectedRepos: [SelectedRepo] = []

    // Debug HR Simulator (only works in DEBUG builds)
    #if DEBUG
    @Published var isSimulatingHR = false
    @Published var manualBPM: Int = 100
    private var simulatorTimer: Timer?
    #endif

    private var statusTimer: Timer?

    private init() {}

    // MARK: - Workout Control

    func startWorkout(repoIds: [String]? = nil) async throws {
        let session = try await APIService.shared.startWorkout(repoIds: repoIds)
        currentSessionId = session.sessionId
        isActive = true
        error = nil

        // Store selected repos
        if let repos = session.selectedRepos {
            selectedRepos = repos
        } else {
            selectedRepos = []
        }

        // Start polling HR status
        startStatusPolling()
    }

    func stopWorkout() async throws {
        try await APIService.shared.stopWorkout()
        currentSessionId = nil
        isActive = false
        // Don't reset currentBPM - keep showing HR from watch
        toolsUnlocked = false
        selectedRepos = []

        // Stop polling
        stopStatusPolling()
    }

    // MARK: - HR Sample Ingestion

    /// Update current BPM from watch - always updates display, only sends to API during active workout
    func updateHeartRate(_ bpm: Int) async {
        // Always update the displayed BPM
        currentBPM = bpm

        // Only send to API if we have an active workout session
        guard let sessionId = currentSessionId, isActive else { return }

        do {
            let status = try await APIService.shared.ingestHRSample(
                sessionId: sessionId,
                bpm: bpm
            )
            toolsUnlocked = status.toolsUnlocked
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Legacy method for backwards compatibility
    func ingestHeartRate(_ bpm: Int) async {
        await updateHeartRate(bpm)
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: Config.hrStatusPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollStatus()
            }
        }
    }

    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private func pollStatus() async {
        do {
            let status = try await APIService.shared.fetchHRStatus()
            toolsUnlocked = status.toolsUnlocked
            // Don't reset currentBPM - it comes from watch regardless of workout state
        } catch {
            // Ignore polling errors
        }
    }

    // MARK: - Check Active Session on Launch

    func checkActiveSession() async {
        do {
            let active = try await APIService.shared.getActiveWorkout()
            if active.active, let sessionId = active.sessionId {
                currentSessionId = sessionId
                isActive = true

                // Restore selected repos
                if let repos = active.selectedRepos {
                    selectedRepos = repos.map { SelectedRepo(id: $0.id, owner: $0.owner, name: $0.name) }
                }

                startStatusPolling()
            }
        } catch {
            // Ignore errors
        }
    }

    // MARK: - Debug HR Simulator

    #if DEBUG
    func toggleHRSimulator() {
        isSimulatingHR.toggle()
        if isSimulatingHR {
            startHRSimulator()
        } else {
            stopHRSimulator()
        }
    }

    /// Set manual heart rate value - immediately updates the display and sends to API if workout is active
    func setManualHeartRate(_ bpm: Int) {
        manualBPM = min(max(bpm, 50), 180)
        // Always update the display via updateHeartRate (which also sends to API if active)
        Task { await updateHeartRate(manualBPM) }
    }

    private func startHRSimulator() {
        // Immediately update display with current manual value
        Task { await updateHeartRate(manualBPM) }

        // Timer periodically sends HR to API when workout is active
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isSimulatingHR else { return }
                // updateHeartRate handles both display update and API call (if active)
                await self.updateHeartRate(self.manualBPM)
            }
        }
    }

    private func stopHRSimulator() {
        simulatorTimer?.invalidate()
        simulatorTimer = nil
    }
    #endif
}
