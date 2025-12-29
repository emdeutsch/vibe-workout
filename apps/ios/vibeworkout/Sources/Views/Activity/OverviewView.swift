import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var apiService: APIService

    @State private var stats: OverviewStats?
    @State private var selectedPeriod: TimePeriod = .month
    @State private var selectedChartMetric: ChartMetric = .duration
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Period selector
                TimePeriodPicker(selectedPeriod: $selectedPeriod)
                    .onChange(of: selectedPeriod) { _, _ in
                        Task { await loadStats() }
                    }

                if isLoading && stats == nil {
                    ProgressView("Loading stats...")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let stats = stats {
                    // Stats cards
                    VStack(spacing: Spacing.md) {
                        WorkoutStatsCard(stats: stats.workout)
                        CodingStatsCard(stats: stats.coding)
                        ToolStatsCard(stats: stats.tools)
                    }

                    // Activity chart
                    ActivityChartSection(
                        chart: stats.chart,
                        selectedMetric: $selectedChartMetric
                    )
                } else if let error = error {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadStats() }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Data", systemImage: "chart.bar")
                    } description: {
                        Text("Complete some workouts to see your stats")
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .refreshable {
            await loadStats()
        }
        .task {
            await loadStats()
        }
    }

    private func loadStats() async {
        isLoading = true
        error = nil

        do {
            stats = try await apiService.fetchOverviewStats(period: selectedPeriod)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Time Period Picker

struct TimePeriodPicker: View {
    @Binding var selectedPeriod: TimePeriod

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(TimePeriod.allCases) { period in
                Button {
                    selectedPeriod = period
                } label: {
                    Text(period.displayName)
                        .font(.subheadline)
                        .fontWeight(selectedPeriod == period ? .semibold : .regular)
                        .foregroundStyle(selectedPeriod == period ? .white : .primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            selectedPeriod == period
                                ? Color.brandPrimary
                                : Color.secondary.opacity(0.15)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Workout Stats Card

struct WorkoutStatsCard: View {
    let stats: WorkoutAggregateStats

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Workout", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(.red)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                StatItem(label: "Time", value: stats.formattedDuration, icon: "clock")
                StatItem(label: "Sessions", value: "\(stats.sessionCount)", icon: "figure.run")
                StatItem(label: "Avg HR", value: "\(stats.avgBpm)", icon: "heart")
                StatItem(label: "Max HR", value: "\(stats.maxBpm)", icon: "arrow.up")
                StatItem(
                    label: "Above",
                    value: formatDuration(stats.timeAboveThresholdSecs),
                    icon: "checkmark.circle",
                    color: .green
                )
                StatItem(
                    label: "Below",
                    value: formatDuration(stats.timeBelowThresholdSecs),
                    icon: "xmark.circle",
                    color: .red
                )
            }

            // Threshold progress bar
            if stats.timeAboveThresholdSecs + stats.timeBelowThresholdSecs > 0 {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: geo.size.width * stats.thresholdPercentage)
                        Rectangle()
                            .fill(Color.red.opacity(0.5))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Coding Stats Card

struct CodingStatsCard: View {
    let stats: CodingAggregateStats

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Coding", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
                .foregroundStyle(.blue)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                StatItem(label: "Commits", value: "\(stats.totalCommits)", icon: "arrow.triangle.branch")
                StatItem(label: "Added", value: "+\(stats.formattedLinesAdded)", icon: "plus", color: .green)
                StatItem(label: "Removed", value: "-\(stats.formattedLinesRemoved)", icon: "minus", color: .red)
                StatItem(label: "PRs", value: "\(stats.totalPrs)", icon: "arrow.triangle.pull")
                StatItem(label: "Merged", value: "\(stats.prsMerged)", icon: "checkmark.circle", color: .purple)
                if let repos = stats.reposCount {
                    StatItem(label: "Repos", value: "\(repos)", icon: "folder")
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Tool Stats Card

struct ToolStatsCard: View {
    let stats: ToolAggregateStats

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Tool Usage", systemImage: "hammer")
                .font(.headline)
                .foregroundStyle(.orange)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                StatItem(label: "Total", value: "\(stats.totalAttempts)", icon: "hand.tap")
                StatItem(label: "Allowed", value: "\(stats.allowed)", icon: "checkmark", color: .green)
                StatItem(label: "Blocked", value: "\(stats.blocked)", icon: "xmark", color: .red)
            }

            // Top tools
            if let topTools = stats.topTools, !topTools.isEmpty {
                Divider()

                Text("Top Tools")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: Spacing.sm) {
                    ForEach(topTools.prefix(4)) { tool in
                        VStack(spacing: 2) {
                            Text(tool.name)
                                .font(.caption)
                                .lineLimit(1)
                            Text("\(tool.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color.opacity(0.7))
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Activity Chart Section

struct ActivityChartSection: View {
    let chart: ActivityChartData
    @Binding var selectedMetric: ChartMetric

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(ChartMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.menu)
            }

            if chart.buckets.isEmpty {
                Text("No activity data")
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(chart.buckets) { bucket in
                        BarMark(
                            x: .value("Date", bucket.formattedDate),
                            y: .value("Value", valueFor(bucket))
                        )
                        .foregroundStyle(colorForMetric.gradient)
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel()
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func valueFor(_ bucket: ActivityBucket) -> Int {
        switch selectedMetric {
        case .duration:
            return bucket.durationSecs / 60 // Show minutes
        case .commits:
            return bucket.commits
        case .lines:
            return bucket.linesAdded + bucket.linesRemoved
        case .tools:
            return bucket.toolCalls ?? 0
        }
    }

    private var colorForMetric: Color {
        switch selectedMetric {
        case .duration:
            return .red
        case .commits:
            return .blue
        case .lines:
            return .green
        case .tools:
            return .orange
        }
    }
}

#Preview {
    OverviewView()
        .environmentObject(APIService.shared)
}
