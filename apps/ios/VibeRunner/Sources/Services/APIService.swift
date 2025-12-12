import Foundation

/// Service for communicating with the VibeRunner backend
class APIService {
    private let baseURL: String
    private var deviceId: String

    init(baseURL: String = Configuration.apiBaseURL) {
        self.baseURL = baseURL
        // Get or create device ID
        if let savedDeviceId = UserDefaults.standard.string(forKey: "deviceId") {
            self.deviceId = savedDeviceId
        } else {
            let newDeviceId = UUID().uuidString
            UserDefaults.standard.set(newDeviceId, forKey: "deviceId")
            self.deviceId = newDeviceId
        }
    }

    /// Get auth token from Supabase
    private var authToken: String? {
        AuthService.shared.accessToken
    }

    // MARK: - Profile

    func getProfile() async throws -> ProfileResponse {
        return try await get("/auth/profile")
    }

    func updatePaceThreshold(seconds: Int) async throws {
        let request = UpdatePaceThresholdRequest(paceThresholdSeconds: seconds)
        let _: ProfileUpdateResponse = try await put("/auth/profile", body: request)
    }

    func getGitHubAuthURL() async throws -> String {
        let response: GitHubAuthResponse = try await get("/auth/github")
        return response.url
    }

    func registerDevice(name: String) async throws -> DeviceResponse {
        let request = RegisterDeviceRequest(name: name)
        return try await post("/auth/devices", body: request)
    }

    // MARK: - Repositories

    func getAvailableRepos() async throws -> [AvailableRepository] {
        let response: AvailableRepositoryListResponse = try await get("/repos/available")
        return response.repositories
    }

    func getGatedRepos() async throws -> [Repository] {
        let response: RepositoryListResponse = try await get("/repos")
        return response.repositories
    }

    func addRepo(_ repo: AvailableRepository) async throws -> Repository {
        let request = AddRepositoryRequest(
            githubRepoId: repo.id,
            owner: repo.owner,
            name: repo.name,
            fullName: repo.fullName
        )
        let response: RepositoryResponse = try await post("/repos", body: request)
        return response.repository
    }

    func removeRepo(id: String) async throws {
        try await delete("/repos/\(id)")
    }

    // MARK: - Heartbeat

    func sendHeartbeat(
        runState: RunState,
        pace: Double?,
        distanceMeters: Double?,
        caloriesBurned: Double?,
        route: [[String: Any]]?,
        location: LocationSample?
    ) async throws -> HeartbeatResponse {
        let request = HeartbeatRequest(
            runState: runState.rawValue,
            currentPace: pace,
            distanceMeters: distanceMeters,
            caloriesBurned: caloriesBurned,
            route: route?.map { RoutePoint(
                lat: $0["lat"] as? Double ?? 0,
                lng: $0["lng"] as? Double ?? 0,
                timestamp: $0["timestamp"] as? Int ?? 0,
                pace: $0["pace"] as? Double
            )},
            location: location.map { LocationData(latitude: $0.latitude, longitude: $0.longitude) }
        )
        return try await post("/heartbeat", body: request)
    }

    func startRun() async throws -> SessionInfo {
        let response: SessionResponse = try await post("/heartbeat/start", body: EmptyBody())
        return response.session
    }

    func endRun(
        distanceMeters: Double?,
        averagePaceSeconds: Double?,
        caloriesBurned: Double?,
        route: [[String: Any]]?,
        healthKitWorkoutId: String?
    ) async throws -> SessionInfo {
        let request = EndRunRequest(
            distanceMeters: distanceMeters,
            averagePaceSeconds: averagePaceSeconds,
            caloriesBurned: caloriesBurned,
            route: route?.map { RoutePoint(
                lat: $0["lat"] as? Double ?? 0,
                lng: $0["lng"] as? Double ?? 0,
                timestamp: $0["timestamp"] as? Int ?? 0,
                pace: $0["pace"] as? Double
            )},
            healthKitWorkoutId: healthKitWorkoutId
        )
        let response: SessionResponse = try await post("/heartbeat/end", body: request)
        return response.session
    }

    func getSessionStatus() async throws -> SessionStatusResponse {
        return try await get("/heartbeat/status")
    }

    // MARK: - Run History

    func getRunHistory(limit: Int = 50, offset: Int = 0) async throws -> RunHistoryResponse {
        return try await get("/runs/history?limit=\(limit)&offset=\(offset)")
    }

    func getRunStats() async throws -> RunStatsResponse {
        return try await get("/runs/stats")
    }

    func getRun(id: String) async throws -> RunDetailResponse {
        return try await get("/runs/\(id)")
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(&request)
        return try await execute(request)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        addHeaders(&request)
        return try await execute(request)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        addHeaders(&request)
        return try await execute(request)
    }

    private func delete(_ path: String) async throws {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(&request)
        let _: EmptyResponse = try await execute(request)
    }

    private func addHeaders(_ request: inout URLRequest) {
        // Add auth token from Supabase
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Add device ID
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Supporting Types

struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}
struct ErrorResponse: Decodable {
    let error: String
}

struct RepositoryResponse: Decodable {
    let repository: Repository
}

enum APIError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        }
    }
}
