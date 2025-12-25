import SwiftUI
import Charts

struct PostWorkoutSummaryView: View {
    let sessionId: String

    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss

    @State private var summary: PostWorkoutSummary?
    @State private var samples: [HRSample] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showDiscardConfirmation = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading summary...")
                } else if let summary = summary {
                    ScrollView {
                        VStack(spacing: Spacing.lg) {
                            // Celebration header
                            celebrationHeader

                            // HR Summary Card
                            hrSummaryCard(summary.session.summary)

                            // HR Sparkline
                            if !samples.isEmpty {
                                hrChartSection
                            }

                            // Coding Summary Card
                            codingSummaryCard(summary)

                            // Repos Breakdown
                            if !summary.repoBreakdown.isEmpty {
                                reposBreakdownSection(summary.repoBreakdown)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.xxl + 100)
                    }
                    .safeAreaInset(edge: .bottom) {
                        actionButtons
                    }
                } else if let error = error {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Error loading summary")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Dismiss") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Workout Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSummary()
            }
            .confirmationDialog(
                "Discard Workout?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    Task { await discardWorkout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this workout and all its data.")
            }
        }
    }

    // MARK: - Celebration Header

    private var celebrationHeader: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Great Session!")
                .font(.title2.weight(.bold))
        }
        .padding(.vertical, Spacing.lg)
    }

    // MARK: - HR Summary Card

    private func hrSummaryCard(_ workoutSummary: WorkoutSummary?) -> some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart Rate")
                    .font(.headline)
                Spacer()
            }

            if let summary = workoutSummary {
                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        Text(summary.formattedDuration)
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .frame(height: 40)

                    VStack(spacing: Spacing.xs) {
                        Text("\(summary.avgBpm)")
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("Avg BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .frame(height: 40)

                    VStack(spacing: Spacing.xs) {
                        Text("\(summary.maxBpm)")
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text("Max BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Threshold bar
                thresholdBar(summary)
            } else {
                Text("No HR data recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func thresholdBar(_ summary: WorkoutSummary) -> some View {
        let totalTime = summary.timeAboveThresholdSecs + summary.timeBelowThresholdSecs
        let abovePercentage = totalTime > 0 ? Double(summary.timeAboveThresholdSecs) / Double(totalTime) : 0

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Above \(summary.thresholdBpm) BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(abovePercentage * 100))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.3))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geometry.size.width * abovePercentage)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - HR Chart Section

    private var hrChartSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Heart Rate Over Time")
                .font(.headline)

            HeartRateChartView(
                dataPoints: samples.toChartPoints(),
                thresholdBpm: summary?.session.summary?.thresholdBpm ?? 100,
                showThreshold: true,
                showRange: false
            )
            .frame(height: 150)
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Coding Summary Card

    private func codingSummaryCard(_ summary: PostWorkoutSummary) -> some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.blue)
                Text("Coding Activity")
                    .font(.headline)
                Spacer()
            }

            if summary.totalCommits > 0 {
                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        HStack(spacing: 2) {
                            Text("+\(summary.totalLinesAdded)")
                                .foregroundStyle(.green)
                        }
                        .font(.title3.weight(.bold).monospacedDigit())
                        Text("Added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: Spacing.xs) {
                        HStack(spacing: 2) {
                            Text("-\(summary.totalLinesRemoved)")
                                .foregroundStyle(.red)
                        }
                        .font(.title3.weight(.bold).monospacedDigit())
                        Text("Removed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: Spacing.xs) {
                        Text("\(summary.totalCommits)")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("Commits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(summary.repoBreakdown.count) \(summary.repoBreakdown.count == 1 ? "repository" : "repositories")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No commits during this workout")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Repos Breakdown Section

    private func reposBreakdownSection(_ repos: [RepoStats]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("By Repository")
                .font(.headline)

            ForEach(repos) { repo in
                repoStatsRow(repo)
            }
        }
        .padding(Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func repoStatsRow(_ repo: RepoStats) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text(repo.fullName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(repo.commitCount) \(repo.commitCount == 1 ? "commit" : "commits")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.md) {
                HStack(spacing: 2) {
                    Text("+\(repo.linesAdded)")
                        .foregroundStyle(.green)
                }
                .font(.caption.monospacedDigit())

                HStack(spacing: 2) {
                    Text("-\(repo.linesRemoved)")
                        .foregroundStyle(.red)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(Spacing.sm)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Save Workout")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)
            .disabled(isSaving)

            Button {
                showDiscardConfirmation = true
            } label: {
                Text("Discard")
                    .foregroundStyle(.red)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
    }

    // MARK: - Data Loading

    private func loadSummary() async {
        isLoading = true
        error = nil

        do {
            async let summaryTask = apiService.fetchPostWorkoutSummary(sessionId: sessionId)
            async let samplesTask = apiService.fetchSessionSamples(sessionId: sessionId)

            let (fetchedSummary, fetchedSamples) = try await (summaryTask, samplesTask)

            summary = fetchedSummary
            samples = fetchedSamples
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func discardWorkout() async {
        isSaving = true

        do {
            try await apiService.discardWorkout(sessionId: sessionId)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    PostWorkoutSummaryView(sessionId: "preview-session")
        .environmentObject(APIService.shared)
}
