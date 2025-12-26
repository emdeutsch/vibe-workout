import SwiftUI

struct WorkoutDetailView: View {
    @EnvironmentObject var apiService: APIService

    let sessionId: String

    @State private var session: WorkoutSessionDetail?
    @State private var samples: [HRSample] = []
    @State private var isLoading = true
    @State private var error: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading workout...")
                    .padding(.top, 100)
            } else if let session = session {
                VStack(spacing: 24) {
                    headerSection(session)

                    if let summary = session.summary {
                        statsSection(summary)
                    }

                    chartSection

                    if !session.commits.isEmpty {
                        codingStatsSection(session.commits)
                        groupedCommitsSection(session.commits)
                    }
                }
                .padding()
            } else if let error = error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            }
        }
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
    }

    // MARK: - Sections

    private func headerSection(_ session: WorkoutSessionDetail) -> some View {
        VStack(spacing: 8) {
            if let startDate = {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: session.startedAt)
            }() {
                Text(dateFormatter.string(from: startDate))
                    .font(.headline)
            }

            HStack(spacing: 8) {
                Image(systemName: sourceIcon(session.source))
                Text(session.source.capitalized)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if session.active {
                Text("In Progress")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statsSection(_ summary: WorkoutSummary) -> some View {
        VStack(spacing: 16) {
            Text("Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(title: "Duration", value: summary.formattedDuration, icon: "clock.fill", color: .blue)
                StatCard(title: "Avg HR", value: "\(summary.avgBpm) BPM", icon: "heart.fill", color: .red)
                StatCard(title: "Max HR", value: "\(summary.maxBpm) BPM", icon: "arrow.up.circle.fill", color: .orange)
                StatCard(title: "Min HR", value: "\(summary.minBpm) BPM", icon: "arrow.down.circle.fill", color: .teal)
            }

            // Threshold time breakdown
            HStack(spacing: 12) {
                ThresholdBar(
                    label: "Above \(summary.thresholdBpm)",
                    seconds: summary.timeAboveThresholdSecs,
                    total: summary.timeAboveThresholdSecs + summary.timeBelowThresholdSecs,
                    color: .green
                )

                ThresholdBar(
                    label: "Below \(summary.thresholdBpm)",
                    seconds: summary.timeBelowThresholdSecs,
                    total: summary.timeAboveThresholdSecs + summary.timeBelowThresholdSecs,
                    color: .red
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate")
                .font(.headline)

            if samples.isEmpty {
                Text("No heart rate data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                HeartRateChartView(
                    dataPoints: samples.toChartPoints(),
                    thresholdBpm: session?.summary?.thresholdBpm ?? 100,
                    showThreshold: true,
                    showRange: false
                )
                .frame(height: 250)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func codingStatsSection(_ commits: [SessionCommit]) -> some View {
        let totalAdded = commits.compactMap { $0.linesAdded }.reduce(0, +)
        let totalRemoved = commits.compactMap { $0.linesRemoved }.reduce(0, +)
        let repoCount = Set(commits.map { "\($0.repoOwner)/\($0.repoName)" }).count

        return VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.blue)
                Text("Coding Activity")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.xs) {
                    Text("+\(totalAdded)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.green)
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: Spacing.xs) {
                    Text("-\(totalRemoved)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.red)
                    Text("Removed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(spacing: Spacing.xs) {
                    Text("\(commits.count)")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text("Commits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(repoCount) \(repoCount == 1 ? "repository" : "repositories")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func groupedCommitsSection(_ commits: [SessionCommit]) -> some View {
        let grouped = Dictionary(grouping: commits) { "\($0.repoOwner)/\($0.repoName)" }
        let sortedKeys = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Commits by Repository")
                .font(.headline)

            ForEach(sortedKeys, id: \.self) { repoKey in
                RepoCommitGroup(
                    repoName: repoKey,
                    commits: grouped[repoKey] ?? []
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func sourceIcon(_ source: String) -> String {
        switch source {
        case "watch": return "applewatch"
        case "ble": return "antenna.radiowaves.left.and.right"
        default: return "heart.fill"
        }
    }

    private func loadData() async {
        isLoading = true
        error = nil

        do {
            async let sessionTask = apiService.fetchWorkoutSession(id: sessionId)
            async let samplesTask = apiService.fetchSessionSamples(sessionId: sessionId)

            let (sessionResult, samplesResult) = try await (sessionTask, samplesTask)
            session = sessionResult
            samples = samplesResult
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Threshold Bar

struct ThresholdBar: View {
    let label: String
    let seconds: Int
    let total: Int
    let color: Color

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(seconds) / Double(total)
    }

    private var formattedTime: String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 8)

            Text(formattedTime)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(sessionId: "preview-session")
            .environmentObject(APIService.shared)
    }
}
