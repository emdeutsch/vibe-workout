import Foundation

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    @Published var profile: Profile?
    @Published var hrStatus: HRStatus?
    @Published var gateRepos: [GateRepo] = []
    @Published var githubStatus: GitHubStatus?
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL: URL
    private let session: URLSession

    private init() {
        self.baseURL = URL(string: Config.apiBaseURL)!
        self.session = URLSession.shared
    }

    // MARK: - Request Helpers

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        guard let token = await AuthService.shared.accessToken else {
            throw APIError.notAuthenticated
        }

        // Use URL(string:relativeTo:) to preserve query strings (appendingPathComponent encodes ? as %3F)
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    // MARK: - Profile

    func fetchProfile() async throws -> Profile {
        let data = try await makeRequest(path: "api/profile")
        let profile = try decode(Profile.self, from: data)
        self.profile = profile
        return profile
    }

    func updateThreshold(_ threshold: Int) async throws {
        let body = try JSONEncoder().encode(["hr_threshold_bpm": threshold])
        _ = try await makeRequest(path: "api/profile/threshold", method: "PATCH", body: body)

        // Refresh profile
        _ = try await fetchProfile()
    }

    // MARK: - Workout

    func fetchSelectableRepos() async throws -> (repos: [SelectableRepo], deletedCount: Int) {
        let data = try await makeRequest(path: "api/gate-repos/selectable")
        let response = try decode(SelectableReposResponse.self, from: data)
        return (response.repos, response.deletedCount ?? 0)
    }

    func startWorkout(source: String = "watch", repoIds: [String]? = nil) async throws -> WorkoutSession {
        var body: [String: Any] = ["source": source]
        if let repoIds = repoIds, !repoIds.isEmpty {
            body["repo_ids"] = repoIds
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await makeRequest(path: "api/workout/start", method: "POST", body: data)
        return try decode(WorkoutSession.self, from: responseData)
    }

    func stopWorkout() async throws -> StopWorkoutResponse {
        let data = try await makeRequest(path: "api/workout/stop", method: "POST")
        return try decode(StopWorkoutResponse.self, from: data)
    }

    func getActiveWorkout() async throws -> ActiveWorkout {
        let data = try await makeRequest(path: "api/workout/active")
        return try decode(ActiveWorkout.self, from: data)
    }

    func ingestHRSample(sessionId: String, bpm: Int, source: String = "watch") async throws -> HRStatus {
        let body = try JSONEncoder().encode([
            "session_id": sessionId,
            "bpm": bpm,
            "source": source
        ] as [String: Any])
        let data = try await makeRequest(path: "api/workout/hr", method: "POST", body: body)
        let status = try decode(HRStatus.self, from: data)
        self.hrStatus = status
        return status
    }

    func fetchHRStatus() async throws -> HRStatus {
        let data = try await makeRequest(path: "api/workout/status")
        let status = try decode(HRStatus.self, from: data)
        self.hrStatus = status
        return status
    }

    // MARK: - Workout History

    func fetchWorkoutSessions(limit: Int = 20, cursor: String? = nil) async throws -> SessionsListResponse {
        var path = "api/workout/sessions?limit=\(limit)"
        if let cursor = cursor {
            path += "&cursor=\(cursor)"
        }
        let data = try await makeRequest(path: path)
        return try decode(SessionsListResponse.self, from: data)
    }

    func fetchWorkoutSession(id: String) async throws -> WorkoutSessionDetail {
        let data = try await makeRequest(path: "api/workout/sessions/\(id)")
        return try decode(WorkoutSessionDetail.self, from: data)
    }

    func fetchSessionSamples(sessionId: String) async throws -> [HRSample] {
        let data = try await makeRequest(path: "api/workout/sessions/\(sessionId)/samples")
        let response = try decode(HRSamplesResponse.self, from: data)
        return response.samples
    }

    func fetchSessionBuckets(sessionId: String) async throws -> [HRBucket] {
        let data = try await makeRequest(path: "api/workout/sessions/\(sessionId)/buckets")
        let response = try decode(HRBucketsResponse.self, from: data)
        return response.buckets
    }

    func fetchPostWorkoutSummary(sessionId: String) async throws -> PostWorkoutSummary {
        let data = try await makeRequest(path: "api/workout/sessions/\(sessionId)/post-summary")
        return try decode(PostWorkoutSummary.self, from: data)
    }

    func discardWorkout(sessionId: String) async throws {
        _ = try await makeRequest(path: "api/workout/sessions/\(sessionId)", method: "DELETE")
    }

    // MARK: - GitHub

    /// Sync GitHub provider token from Supabase OAuth to backend
    func syncGitHubToken(providerToken: String) async throws {
        let body = try JSONEncoder().encode(["provider_token": providerToken])
        _ = try await makeRequest(path: "api/github/sync-token", method: "POST", body: body)
    }

    func fetchGitHubStatus() async throws -> GitHubStatus {
        let data = try await makeRequest(path: "api/github/status")
        let status = try decode(GitHubStatus.self, from: data)
        self.githubStatus = status
        return status
    }

    func fetchOrganizations() async throws -> [GitHubOrg] {
        let data = try await makeRequest(path: "api/github/orgs")
        let response = try decode(GitHubOrgsResponse.self, from: data)
        return response.orgs
    }

    func disconnectGitHub() async throws {
        _ = try await makeRequest(path: "api/github/disconnect", method: "DELETE")
        self.githubStatus = GitHubStatus(connected: false, username: nil, scopes: nil, updatedAt: nil)
    }

    // MARK: - Gate Repos

    func fetchGateRepos() async throws -> [GateRepo] {
        let data = try await makeRequest(path: "api/gate-repos")
        let response = try decode(GateReposResponse.self, from: data)
        self.gateRepos = response.repos
        return response.repos
    }

    struct CreateGateRepoParams {
        var name: String
        var description: String?
        var isPrivate: Bool = true
        var org: String?

        // Repository features
        var hasIssues: Bool?
        var hasWiki: Bool?
        var hasProjects: Bool?

        // Templates
        var licenseTemplate: String?
        var gitignoreTemplate: String?

        // Merge settings
        var allowSquashMerge: Bool?
        var allowMergeCommit: Bool?
        var allowRebaseMerge: Bool?
        var deleteBranchOnMerge: Bool?

        // Auto-install GitHub App
        var autoInstallApp: Bool = true
    }

    func createGateRepo(params: CreateGateRepoParams) async throws -> CreateGateRepoResponse {
        var body: [String: Any] = [
            "name": params.name,
            "private": params.isPrivate,
            "auto_install_app": params.autoInstallApp
        ]

        if let description = params.description {
            body["description"] = description
        }
        if let org = params.org {
            body["org"] = org
        }
        if let hasIssues = params.hasIssues {
            body["has_issues"] = hasIssues
        }
        if let hasWiki = params.hasWiki {
            body["has_wiki"] = hasWiki
        }
        if let hasProjects = params.hasProjects {
            body["has_projects"] = hasProjects
        }
        if let license = params.licenseTemplate {
            body["license_template"] = license
        }
        if let gitignore = params.gitignoreTemplate {
            body["gitignore_template"] = gitignore
        }
        if let allowSquash = params.allowSquashMerge {
            body["allow_squash_merge"] = allowSquash
        }
        if let allowMerge = params.allowMergeCommit {
            body["allow_merge_commit"] = allowMerge
        }
        if let allowRebase = params.allowRebaseMerge {
            body["allow_rebase_merge"] = allowRebase
        }
        if let deleteBranch = params.deleteBranchOnMerge {
            body["delete_branch_on_merge"] = deleteBranch
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let responseData = try await makeRequest(path: "api/gate-repos", method: "POST", body: data)
        let response = try decode(CreateGateRepoResponse.self, from: responseData)

        // Refresh repos list
        _ = try await fetchGateRepos()

        return response
    }

    // Convenience method for simple repo creation (backwards compatibility)
    func createGateRepo(name: String, description: String? = nil, isPrivate: Bool = true) async throws -> CreateGateRepoResponse {
        var params = CreateGateRepoParams(name: name)
        params.description = description
        params.isPrivate = isPrivate
        return try await createGateRepo(params: params)
    }

    func deleteGateRepo(id: String) async throws {
        _ = try await makeRequest(path: "api/gate-repos/\(id)", method: "DELETE")

        // Refresh repos list
        _ = try await fetchGateRepos()
    }

    func toggleGateRepo(id: String, active: Bool) async throws {
        let body = try JSONEncoder().encode(["active": active])
        _ = try await makeRequest(path: "api/gate-repos/\(id)", method: "PATCH", body: body)

        // Refresh repos list
        _ = try await fetchGateRepos()
    }

    func getGateRepoInstallURL(id: String) async throws -> InstallUrlResponse {
        let data = try await makeRequest(path: "api/gate-repos/\(id)/install-url")
        return try decode(InstallUrlResponse.self, from: data)
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// Helper extension for encoding dictionaries
extension JSONEncoder {
    func encode(_ dictionary: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dictionary)
    }
}
