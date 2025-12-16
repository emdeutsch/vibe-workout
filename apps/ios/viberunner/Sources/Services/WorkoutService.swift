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
    private var simulatorTimer: Timer?
    private var simulatedBPM: Int = 85
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
        currentBPM = 0
        toolsUnlocked = false
        selectedRepos = []

        // Stop polling
        stopStatusPolling()
    }

    // MARK: - HR Sample Ingestion

    func ingestHeartRate(_ bpm: Int) async {
        guard let sessionId = currentSessionId else { return }

        do {
            let status = try await APIService.shared.ingestHRSample(
                sessionId: sessionId,
                bpm: bpm
            )
            currentBPM = bpm
            toolsUnlocked = status.toolsUnlocked
        } catch {
            self.error = error.localizedDescription
        }
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
            if !isActive {
                currentBPM = 0
            }
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

    private func startHRSimulator() {
        simulatedBPM = Int.random(in: 80...95)
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isSimulatingHR, self.isActive else { return }

                // Simulate realistic HR variation
                let change = Int.random(in: -5...8)
                self.simulatedBPM = min(max(self.simulatedBPM + change, 70), 165)

                await self.ingestHeartRate(self.simulatedBPM)
            }
        }
    }

    private func stopHRSimulator() {
        simulatorTimer?.invalidate()
        simulatorTimer = nil
    }
    #endif
}
