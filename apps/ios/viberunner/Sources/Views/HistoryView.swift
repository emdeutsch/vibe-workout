import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var apiService: APIService

    @State private var sessions: [WorkoutSessionListItem] = []
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sessions.isEmpty {
                    ProgressView("Loading workouts...")
                } else if sessions.isEmpty {
                    emptyState
                } else {
                    sessionsList
                }
            }
            .navigationTitle("History")
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
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workouts Yet", systemImage: "figure.run")
        } description: {
            Text("Start a workout to see your history here")
        }
    }

    private var sessionsList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink(destination: WorkoutDetailView(sessionId: session.id)) {
                    SessionRowView(session: session)
                }
            }

            if hasMore {
                Button {
                    Task {
                        await loadMore()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Load More")
                        }
                        Spacer()
                    }
                }
                .disabled(isLoading)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadSessions(refresh: Bool = false) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let response = try await apiService.fetchWorkoutSessions()
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
            let response = try await apiService.fetchWorkoutSessions(cursor: cursor)
            sessions.append(contentsOf: response.sessions)
            hasMore = response.hasMore
            nextCursor = response.nextCursor
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: WorkoutSessionListItem

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date and status
            HStack {
                if let date = session.startDate {
                    Text(dateFormatter.string(from: date))
                        .font(.headline)
                } else {
                    Text(session.startedAt)
                        .font(.headline)
                }

                Spacer()

                if session.active {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green, in: Capsule())
                }
            }

            // Summary stats
            if let summary = session.summary {
                HStack(spacing: 16) {
                    StatPill(
                        icon: "clock",
                        value: summary.formattedDuration,
                        color: .blue
                    )

                    StatPill(
                        icon: "heart.fill",
                        value: "\(summary.avgBpm)",
                        color: .red
                    )

                    StatPill(
                        icon: "arrow.up",
                        value: "\(summary.maxBpm)",
                        color: .orange
                    )
                }
            } else {
                Text("No summary available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Commits indicator
            if session.commitCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)

                    Text("\(session.commitCount) commit\(session.commitCount == 1 ? "" : "s")")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

#Preview {
    HistoryView()
        .environmentObject(APIService.shared)
}
