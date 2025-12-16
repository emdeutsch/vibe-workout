import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var watchConnectivity: WatchConnectivityService
    @EnvironmentObject var apiService: APIService

    @State private var showingError = false
    @State private var showingRepoSelector = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Status card
                StatusCard(
                    isActive: workoutService.isActive,
                    bpm: workoutService.currentBPM,
                    toolsUnlocked: workoutService.toolsUnlocked,
                    threshold: apiService.profile?.hrThresholdBpm ?? Config.defaultHRThreshold
                )

                // Selected repos (when workout is active)
                if workoutService.isActive && !workoutService.selectedRepos.isEmpty {
                    SelectedReposView(repos: workoutService.selectedRepos)
                }

                // Watch connectivity status
                WatchStatusView()

                // Debug HR Simulator (only in DEBUG builds)
                #if DEBUG
                DebugHRSimulatorView()
                #endif

                Spacer()

                // Control buttons
                if workoutService.isActive {
                    Button(role: .destructive) {
                        Task {
                            do {
                                watchConnectivity.sendStopWorkout()
                                try await workoutService.stopWorkout()
                            } catch {
                                showingError = true
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop Workout")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    Button {
                        showingRepoSelector = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Workout")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding()
            .navigationTitle("Workout")
            .task {
                // Check for active session on appear
                await workoutService.checkActiveSession()

                // Fetch profile for threshold
                try? await apiService.fetchProfile()
            }
            .sheet(isPresented: $showingRepoSelector) {
                RepoSelectorSheet { selectedRepoIds in
                    Task {
                        do {
                            try await workoutService.startWorkout(repoIds: selectedRepoIds)
                            watchConnectivity.sendStartWorkout()
                        } catch {
                            showingError = true
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(workoutService.error ?? "An error occurred")
            }
        }
    }
}

// MARK: - Selected Repos View

struct SelectedReposView: View {
    let repos: [SelectedRepo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Repos")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(repos) { repo in
                    Text(repo.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.green.opacity(0.15))
                        )
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Repo Selector Sheet

struct RepoSelectorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var apiService: APIService

    @State private var selectableRepos: [SelectableRepo] = []
    @State private var selectedRepoIds: Set<String> = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var deletedCount = 0

    let onStart: ([String]) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading repos...")
                } else if selectableRepos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No Repos Available")
                            .font(.headline)

                        Text("Create a gate repo and install the GitHub App to enable HR-gated coding.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        // Show deleted repos notice if any were removed
                        if deletedCount > 0 {
                            Section {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("\(deletedCount) repo\(deletedCount == 1 ? " was" : "s were") removed (deleted from GitHub)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section {
                            ForEach(selectableRepos) { repo in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(repo.name)
                                            .font(.headline)
                                        Text(repo.owner)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selectedRepoIds.contains(repo.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedRepoIds.contains(repo.id) {
                                        selectedRepoIds.remove(repo.id)
                                    } else {
                                        selectedRepoIds.insert(repo.id)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Repos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(Array(selectedRepoIds))
                        dismiss()
                    }
                    .disabled(selectedRepoIds.isEmpty)
                }
            }
            .task {
                await loadRepos()
            }
        }
    }

    private func loadRepos() async {
        isLoading = true
        do {
            let result = try await apiService.fetchSelectableRepos()
            selectableRepos = result.repos
            deletedCount = result.deletedCount

            // Auto-select all repos by default
            selectedRepoIds = Set(selectableRepos.map { $0.id })
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let isActive: Bool
    let bpm: Int
    let toolsUnlocked: Bool
    let threshold: Int

    var body: some View {
        VStack(spacing: 20) {
            // Heart rate display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(bpm)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(bpm >= threshold ? .green : .red)

                Text("BPM")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(toolsUnlocked ? .green : .red)
                    .frame(width: 12, height: 12)

                Text(toolsUnlocked ? "Tools Unlocked" : "Tools Locked")
                    .font(.headline)
                    .foregroundStyle(toolsUnlocked ? .green : .red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(toolsUnlocked ? .green.opacity(0.15) : .red.opacity(0.15))
            )

            // Threshold indicator
            Text("Threshold: \(threshold) BPM")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Workout status
            if isActive {
                HStack {
                    Image(systemName: "figure.run")
                    Text("Workout Active")
                }
                .font(.caption)
                .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Watch Status

struct WatchStatusView: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(watchConnectivity.isReachable ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(watchConnectivity.isWatchAppInstalled ? "Apple Watch" : "Watch Not Found")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(watchConnectivity.isReachable ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastBPM = watchConnectivity.lastReceivedBPM {
                Text("\(lastBPM)")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Debug HR Simulator View

#if DEBUG
struct DebugHRSimulatorView: View {
    @EnvironmentObject var workoutService: WorkoutService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(workoutService.isSimulatingHR ? .pink : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("HR Simulator")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(workoutService.isSimulatingHR ? "Generating fake HR data" : "Tap to simulate heart rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { workoutService.isSimulatingHR },
                set: { _ in workoutService.toggleHRSimulator() }
            ))
            .labelsHidden()
            .tint(.pink)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.pink.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.pink.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
#endif

#Preview {
    WorkoutView()
        .environmentObject(WorkoutService.shared)
        .environmentObject(WatchConnectivityService.shared)
        .environmentObject(APIService.shared)
}
