import SwiftUI

/// Sessions list view - wraps the existing workout history functionality
/// This is the "Sessions" segment in the Activity tab
struct SessionsListView: View {
    @EnvironmentObject var apiService: APIService

    @State private var sessions: [WorkoutSessionListItem] = []
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                ProgressView("Loading workouts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workouts Yet", systemImage: "figure.run")
        } description: {
            Text("Start a workout to see your history here")
        }
    }

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(sessions) { session in
                    NavigationLink(destination: WorkoutDetailView(sessionId: session.id)) {
                        WorkoutHistoryCard(session: session)
                    }
                    .buttonStyle(.plain)
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
                                    .font(.subheadline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, Spacing.md)
                    }
                    .disabled(isLoading)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
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

#Preview {
    NavigationStack {
        SessionsListView()
            .environmentObject(APIService.shared)
    }
}
