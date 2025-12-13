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

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
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

    func startWorkout(source: String = "watch") async throws -> WorkoutSession {
        let body = try JSONEncoder().encode(["source": source])
        let data = try await makeRequest(path: "api/workout/start", method: "POST", body: body)
        return try decode(WorkoutSession.self, from: data)
    }

    func stopWorkout() async throws {
        _ = try await makeRequest(path: "api/workout/stop", method: "POST")
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

    // MARK: - GitHub

    func startGitHubConnect() async throws -> GitHubOAuthStart {
        let data = try await makeRequest(path: "api/github/connect")
        return try decode(GitHubOAuthStart.self, from: data)
    }

    func completeGitHubConnect(code: String, state: String) async throws {
        let body = try JSONEncoder().encode(["code": code, "state": state])
        _ = try await makeRequest(path: "api/github/callback", method: "POST", body: body)

        // Refresh status
        _ = try await fetchGitHubStatus()
    }

    func fetchGitHubStatus() async throws -> GitHubStatus {
        let data = try await makeRequest(path: "api/github/status")
        let status = try decode(GitHubStatus.self, from: data)
        self.githubStatus = status
        return status
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

    func createGateRepo(name: String, description: String? = nil, isPrivate: Bool = true) async throws -> CreateGateRepoResponse {
        var params: [String: Any] = ["name": name, "private": isPrivate]
        if let description = description {
            params["description"] = description
        }
        let body = try JSONSerialization.data(withJSONObject: params)
        let data = try await makeRequest(path: "api/gate-repos", method: "POST", body: body)
        let response = try decode(CreateGateRepoResponse.self, from: data)

        // Refresh repos list
        _ = try await fetchGateRepos()

        return response
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
