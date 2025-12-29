import SwiftUI

struct ProjectsListView: View {
    @EnvironmentObject var apiService: APIService

    @State private var projects: [ProjectStats] = []
    @State private var selectedPeriod: TimePeriod = .all
    @State private var sortOrder: SortOrder = .recent
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var error: String?

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case time = "Time"
        case commits = "Commits"

        var id: String { rawValue }

        var apiValue: String {
            switch self {
            case .recent: return "recent"
            case .time: return "time"
            case .commits: return "commits"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .onChange(of: selectedPeriod) { _, _ in
                Task { await loadProjects(refresh: true) }
            }
            .onChange(of: sortOrder) { _, _ in
                Task { await loadProjects(refresh: true) }
            }

            // Content
            if isLoading && projects.isEmpty {
                ProgressView("Loading projects...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder")
                } description: {
                    Text("Complete workouts with commits to see project stats")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(projects) { project in
                            NavigationLink(destination: ProjectDetailView(repoFullName: project.repoFullName)) {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                        }

                        if hasMore {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Text("Load More")
                                        .font(.subheadline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .refreshable {
                    await loadProjects(refresh: true)
                }
            }
        }
        .task {
            await loadProjects()
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func loadProjects(refresh: Bool = false) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        if refresh {
            nextCursor = nil
        }

        do {
            let response = try await apiService.fetchProjects(
                period: selectedPeriod,
                sort: sortOrder.apiValue
            )
            projects = response.projects
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
            let response = try await apiService.fetchProjects(
                period: selectedPeriod,
                sort: sortOrder.apiValue,
                cursor: cursor
            )
            projects.append(contentsOf: response.projects)
            hasMore = response.hasMore
            nextCursor = response.nextCursor
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Project Card

struct ProjectCard: View {
    let project: ProjectStats

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(project.repoFullName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(project.formattedLastActive)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Stats grid
            HStack(spacing: Spacing.lg) {
                // Workout stats
                VStack(alignment: .leading, spacing: 4) {
                    Label("Workout", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Spacing.sm) {
                        MiniStat(icon: "clock", value: project.workout.formattedDuration)
                        MiniStat(icon: "heart", value: "\(project.workout.avgBpm)")
                    }
                }

                Divider()

                // Coding stats
                VStack(alignment: .leading, spacing: 4) {
                    Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Spacing.sm) {
                        MiniStat(icon: "arrow.triangle.branch", value: "\(project.coding.totalCommits)")
                        Text("+\(project.coding.linesAdded)/-\(project.coding.linesRemoved)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Tool stats (if any)
            if project.tools.totalAttempts > 0 {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "hammer")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(project.tools.totalAttempts) tools")
                        .font(.caption)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(project.tools.allowed) allowed")
                        .font(.caption)
                        .foregroundStyle(.green)
                    if project.tools.blocked > 0 {
                        Text("\(project.tools.blocked) blocked")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Mini Stat

struct MiniStat: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    NavigationStack {
        ProjectsListView()
            .environmentObject(APIService.shared)
    }
}
