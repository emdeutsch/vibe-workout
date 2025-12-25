import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var watchConnectivity: WatchConnectivityService
    @EnvironmentObject var apiService: APIService

    @State private var showingError = false
    @State private var showingRepoSelector = false
    @State private var showingStopConfirmation = false
    @State private var showingPostWorkoutSummary = false
    @State private var completedSessionId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Heart rate card - adapts based on workout state
                    HeartRateCard(
                        isActive: workoutService.isActive,
                        bpm: workoutService.currentBPM,
                        toolsUnlocked: workoutService.toolsUnlocked,
                        threshold: apiService.profile?.hrThresholdBpm ?? Config.defaultHRThreshold
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: workoutService.isActive)

                    // Selected repos - only when active, with horizontal scroll
                    if workoutService.isActive && !workoutService.selectedRepos.isEmpty {
                        ActiveReposSection(repos: workoutService.selectedRepos)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Watch connectivity status
                    WatchConnectionCard()

                    // Debug HR Simulator (only in DEBUG builds)
                    #if DEBUG
                    DebugHRSimulatorCard()
                    #endif
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl + 80) // Space for button
            }
            .safeAreaInset(edge: .bottom) {
                workoutActionButton
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("Workout")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: workoutService.isActive)
            .task {
                await workoutService.checkActiveSession()
                try? await apiService.fetchProfile()
            }
            .sheet(isPresented: $showingRepoSelector) {
                RepoSelectorSheet { selectedRepoIds in
                    Task {
                        do {
                            try await workoutService.startWorkout(repoIds: selectedRepoIds)
                            watchConnectivity.sendWorkoutStarted()
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
            .confirmationDialog(
                "End Workout?",
                isPresented: $showingStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("End & View Summary", role: .destructive) {
                    Task { await endWorkoutAndShowSummary() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll review your stats before saving.")
            }
            .fullScreenCover(isPresented: $showingPostWorkoutSummary) {
                if let sessionId = completedSessionId {
                    PostWorkoutSummaryView(sessionId: sessionId)
                        .environmentObject(apiService)
                }
            }
        }
    }

    // MARK: - End Workout Flow

    private func endWorkoutAndShowSummary() async {
        watchConnectivity.sendWorkoutStopped()
        let sessionId = try? await workoutService.stopWorkout()

        if let sessionId = sessionId {
            completedSessionId = sessionId
            showingPostWorkoutSummary = true
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var workoutActionButton: some View {
        if workoutService.isActive {
            Button {
                showingStopConfirmation = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "stop.fill")
                    Text("Stop Workout")
                }
            }
            .buttonStyle(.destructive)
        } else {
            Button {
                showingRepoSelector = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "play.fill")
                    Text("Start Workout")
                }
            }
            .buttonStyle(.primary)
        }
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
                    VStack(spacing: Spacing.md) {
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
                        if deletedCount > 0 {
                            Section {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "trash.circle.fill")
                                        .foregroundStyle(Color.statusWarning)
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
                                            .foregroundStyle(Color.statusSuccess)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedRepoIds.contains(repo.id) {
                                            selectedRepoIds.remove(repo.id)
                                        } else {
                                            selectedRepoIds.insert(repo.id)
                                        }
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
            selectedRepoIds = Set(selectableRepos.map { $0.id })
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    WorkoutView()
        .environmentObject(WorkoutService.shared)
        .environmentObject(WatchConnectivityService.shared)
        .environmentObject(APIService.shared)
}
