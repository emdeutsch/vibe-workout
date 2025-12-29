import SwiftUI
import Charts

struct ProjectDetailView: View {
    @EnvironmentObject var apiService: APIService

    let repoFullName: String

    @State private var detail: ProjectDetail?
    @State private var selectedPeriod: TimePeriod = .all
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if isLoading && detail == nil {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let detail = detail {
                    // Period selector
                    TimePeriodPicker(selectedPeriod: $selectedPeriod)
                        .onChange(of: selectedPeriod) { _, _ in
                            Task { await loadDetail() }
                        }

                    // Header
                    ProjectHeaderView(detail: detail)

                    // Stats cards
                    WorkoutStatsCard(stats: detail.workout)
                    CodingStatsCard(stats: detail.coding)
                    ToolStatsCard(stats: detail.tools)

                    // Activity chart
                    ProjectChartView(chart: detail.chart)

                    // Recent sessions
                    if !detail.recentSessions.isEmpty {
                        RecentSessionsSection(
                            sessions: detail.recentSessions,
                            hasMore: detail.hasMoreSessions,
                            repoFullName: repoFullName
                        )
                    }
                } else if let error = error {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadDetail() }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .navigationTitle(repoFullName.components(separatedBy: "/").last ?? repoFullName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadDetail()
        }
        .task {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        error = nil

        do {
            detail = try await apiService.fetchProjectDetail(
                repoFullName: repoFullName,
                period: selectedPeriod
            )
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Project Header

struct ProjectHeaderView: View {
    let detail: ProjectDetail

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.repoFullName)
                        .font(.headline)

                    if let lastActive = detail.lastActiveDate {
                        Text("Last active: \(formatDate(lastActive))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let url = detail.htmlUrl, let urlObj = URL(string: url) {
                    Link(destination: urlObj) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.title3)
                    }
                }
            }

            HStack(spacing: Spacing.md) {
                Label("\(detail.workout.sessionCount) sessions", systemImage: "figure.run")
                Label("\(detail.coding.totalCommits) commits", systemImage: "arrow.triangle.branch")
                if detail.coding.totalPrs > 0 {
                    Label("\(detail.coding.totalPrs) PRs", systemImage: "arrow.triangle.pull")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Project Chart

struct ProjectChartView: View {
    let chart: ActivityChartData

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Activity")
                .font(.headline)

            if chart.buckets.isEmpty {
                Text("No activity data")
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(chart.buckets) { bucket in
                        BarMark(
                            x: .value("Date", bucket.formattedDate),
                            y: .value("Commits", bucket.commits)
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                }
                .frame(height: 120)
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
}

// MARK: - Recent Sessions Section

struct RecentSessionsSection: View {
    let sessions: [ProjectSessionSummary]
    let hasMore: Bool
    let repoFullName: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Recent Sessions")
                    .font(.headline)
                Spacer()
                if hasMore {
                    NavigationLink(destination: ProjectSessionsListView(repoFullName: repoFullName)) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
            }

            ForEach(sessions) { session in
                NavigationLink(destination: WorkoutDetailView(sessionId: session.id)) {
                    ProjectSessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Project Session Row

struct ProjectSessionRow: View {
    let session: ProjectSessionSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.formattedDate)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: Spacing.sm) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label("\(session.avgBpm) avg", systemImage: "heart")
                    Label("\(session.commits) commits", systemImage: "arrow.triangle.branch")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Project Sessions List View (full list)

struct ProjectSessionsListView: View {
    @EnvironmentObject var apiService: APIService

    let repoFullName: String

    @State private var sessions: [ProjectSessionSummary] = []
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                ProgressView("Loading sessions...")
            } else if sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "figure.run")
                } description: {
                    Text("No workout sessions found for this project")
                }
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink(destination: WorkoutDetailView(sessionId: session.id)) {
                            ProjectSessionRow(session: session)
                        }
                    }

                    if hasMore {
                        Button("Load More") {
                            Task { await loadMore() }
                        }
                        .disabled(isLoading)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Sessions")
        .task {
            await loadSessions()
        }
        .refreshable {
            await loadSessions(refresh: true)
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func loadSessions(refresh: Bool = false) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        if refresh {
            nextCursor = nil
        }

        do {
            let response = try await apiService.fetchProjectSessions(repoFullName: repoFullName)
            sessions = response.sessions
            hasMore = response.hasMore
            nextCursor = response.nextCursor
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadMore() async {
        guard !isLoading, let cursor = nextCursor else { return }

        isLoading = true

        do {
            let response = try await apiService.fetchProjectSessions(
                repoFullName: repoFullName,
                cursor: cursor
            )
            sessions.append(contentsOf: response.sessions)
            hasMore = response.hasMore
            nextCursor = response.nextCursor
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ProjectDetailView(repoFullName: "emdeutsch/vibe-workout")
            .environmentObject(APIService.shared)
    }
}
