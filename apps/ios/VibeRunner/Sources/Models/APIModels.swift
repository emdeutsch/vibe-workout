import Foundation

// MARK: - Profile

struct ProfileResponse: Codable {
    let profile: ProfileInfo
    var githubConnected: Bool { profile.githubUsername != nil }
    var paceThresholdSeconds: Int { profile.paceThresholdSeconds }
}

struct ProfileInfo: Codable {
    let id: String
    let email: String?
    let githubUsername: String?
    let paceThresholdSeconds: Int
}

struct UpdatePaceThresholdRequest: Codable {
    let paceThresholdSeconds: Int
}

struct ProfileUpdateResponse: Codable {
    let profile: ProfileInfo
}

// MARK: - Device

struct RegisterDeviceRequest: Codable {
    let name: String
}

struct DeviceResponse: Codable {
    let device: DeviceInfo
}

struct DeviceInfo: Codable {
    let id: String
    let name: String
}

// MARK: - GitHub

struct GitHubAuthResponse: Codable {
    let url: String
}

// MARK: - Repositories

struct RepositoryListResponse: Codable {
    let repositories: [Repository]
}

struct Repository: Codable, Identifiable {
    let id: String
    let githubRepoId: Int
    let owner: String
    let name: String
    let fullName: String
    let rulesetId: Int?
    let gatingEnabled: Bool
}

struct AvailableRepository: Codable, Identifiable {
    let id: Int
    let name: String
    let fullName: String
    let owner: String
    let `private`: Bool
    let defaultBranch: String
    let isGated: Bool
}

struct AvailableRepositoryListResponse: Codable {
    let repositories: [AvailableRepository]
}

struct AddRepositoryRequest: Codable {
    let githubRepoId: Int
    let owner: String
    let name: String
    let fullName: String
}

// MARK: - Heartbeat

struct HeartbeatRequest: Codable {
    let runState: String
    let currentPace: Double?
    let distanceMeters: Double?
    let caloriesBurned: Double?
    let route: [RoutePoint]?
    let location: LocationData?
}

struct RoutePoint: Codable {
    let lat: Double
    let lng: Double
    let timestamp: Int
    let pace: Double?
}

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
}

struct HeartbeatResponse: Codable {
    let success: Bool
    let serverTime: Int
    let stateAcknowledged: String
    let githubWritesEnabled: Bool
    let paceThresholdSeconds: Int
}

// MARK: - Session

struct SessionResponse: Codable {
    let session: SessionInfo
}

struct SessionInfo: Codable {
    let id: String
    let startedAt: String
    let currentState: String?
    let paceThresholdSeconds: Int?
    let endedAt: String?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let averagePaceSeconds: Double?
}

struct EndRunRequest: Codable {
    let distanceMeters: Double?
    let averagePaceSeconds: Double?
    let caloriesBurned: Double?
    let route: [RoutePoint]?
    let healthKitWorkoutId: String?
}

struct SessionStatusResponse: Codable {
    let device: DeviceStatus?
    let session: SessionStatusInfo?
    let githubWritesEnabled: Bool
    let paceThresholdSeconds: Int
}

struct DeviceStatus: Codable {
    let id: String
    let lastHeartbeat: String?
    let lastRunState: String?
}

struct SessionStatusInfo: Codable {
    let id: String
    let startedAt: String
    let currentState: String
    let averagePace: Double?
    let distanceMeters: Double?
}

// MARK: - Run History

struct RunHistoryResponse: Codable {
    let runs: [RunRecord]
}

struct RunRecord: Codable, Identifiable {
    let id: String
    let startedAt: String
    let endedAt: String?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let averagePaceSeconds: Double?
    let caloriesBurned: Double?
    let paceThresholdSeconds: Int?
    let route: [RoutePoint]?
    let healthKitWorkoutId: String?
}

struct RunStatsResponse: Codable {
    let totalRuns: Int
    let totalDistanceMeters: Double
    let totalDurationSeconds: Int
    let averagePaceSeconds: Double?
    let totalDistanceMiles: Double
    let totalDurationMinutes: Int
}

struct RunDetailResponse: Codable {
    let run: RunRecord
}
