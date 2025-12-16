import Foundation

// MARK: - Profile

struct Profile: Codable {
    let userId: String
    let hrThresholdBpm: Int
    let githubConnected: Bool
    let githubUsername: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case hrThresholdBpm = "hr_threshold_bpm"
        case githubConnected = "github_connected"
        case githubUsername = "github_username"
    }
}

// MARK: - HR Status

struct HRStatus: Codable {
    let bpm: Int
    let thresholdBpm: Int
    let hrOk: Bool
    let expiresAt: String
    let toolsUnlocked: Bool

    enum CodingKeys: String, CodingKey {
        case bpm
        case thresholdBpm = "threshold_bpm"
        case hrOk = "hr_ok"
        case expiresAt = "expires_at"
        case toolsUnlocked = "tools_unlocked"
    }
}

// MARK: - Workout Session

struct WorkoutSession: Codable {
    let sessionId: String
    let startedAt: String
    let selectedRepos: [SelectedRepo]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case startedAt = "started_at"
        case selectedRepos = "selected_repos"
    }
}

struct ActiveWorkout: Codable {
    let active: Bool
    let sessionId: String?
    let startedAt: String?
    let source: String?
    let selectedRepos: [SelectedRepo]?

    enum CodingKeys: String, CodingKey {
        case active
        case sessionId = "session_id"
        case startedAt = "started_at"
        case source
        case selectedRepos = "selected_repos"
    }
}

// Repo selected for a workout session
struct SelectedRepo: Codable, Identifiable {
    let id: String
    let owner: String
    let name: String

    var fullName: String {
        "\(owner)/\(name)"
    }
}

// Repo available for selection (has GitHub App installed)
struct SelectableRepo: Codable, Identifiable {
    let id: String
    let owner: String
    let name: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case id, owner, name
        case fullName = "full_name"
    }
}

struct SelectableReposResponse: Codable {
    let repos: [SelectableRepo]
    let deletedCount: Int?

    enum CodingKeys: String, CodingKey {
        case repos
        case deletedCount = "deleted_count"
    }
}

// MARK: - Gate Repo

struct GateRepo: Codable, Identifiable {
    let id: String
    let owner: String
    let name: String
    let userKey: String
    let signalRef: String
    let active: Bool
    let githubAppInstalled: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, owner, name, active
        case userKey = "user_key"
        case signalRef = "signal_ref"
        case githubAppInstalled = "github_app_installed"
        case createdAt = "created_at"
    }

    var fullName: String {
        "\(owner)/\(name)"
    }
}

struct CreateGateRepoResponse: Codable {
    let id: String
    let owner: String
    let name: String
    let userKey: String
    let signalRef: String
    let htmlUrl: String
    let needsAppInstall: Bool
    let installUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, owner, name
        case userKey = "user_key"
        case signalRef = "signal_ref"
        case htmlUrl = "html_url"
        case needsAppInstall = "needs_app_install"
        case installUrl = "install_url"
    }
}

struct GateReposResponse: Codable {
    let repos: [GateRepo]
}

// MARK: - GitHub

struct GitHubOrg: Codable, Identifiable {
    let id: Int
    let login: String
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case id, login
        case avatarUrl = "avatar_url"
    }
}

struct GitHubOrgsResponse: Codable {
    let orgs: [GitHubOrg]
}

struct GitHubStatus: Codable {
    let connected: Bool
    let username: String?
    let scopes: [String]?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case connected, username, scopes
        case updatedAt = "updated_at"
    }
}

struct GitHubRepo: Codable, Identifiable {
    let id: Int
    let fullName: String
    let name: String
    let owner: String
    let isPrivate: Bool
    let htmlUrl: String
    let description: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, owner, description
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlUrl = "html_url"
        case updatedAt = "updated_at"
    }
}

// MARK: - Workout History

struct WorkoutSummary: Codable {
    let durationSecs: Int
    let avgBpm: Int
    let maxBpm: Int
    let minBpm: Int
    let timeAboveThresholdSecs: Int
    let timeBelowThresholdSecs: Int
    let thresholdBpm: Int
    let totalSamples: Int

    enum CodingKeys: String, CodingKey {
        case durationSecs = "duration_secs"
        case avgBpm = "avg_bpm"
        case maxBpm = "max_bpm"
        case minBpm = "min_bpm"
        case timeAboveThresholdSecs = "time_above_threshold_secs"
        case timeBelowThresholdSecs = "time_below_threshold_secs"
        case thresholdBpm = "threshold_bpm"
        case totalSamples = "total_samples"
    }

    var formattedDuration: String {
        let hours = durationSecs / 3600
        let minutes = (durationSecs % 3600) / 60
        let seconds = durationSecs % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct WorkoutSessionListItem: Codable, Identifiable {
    let id: String
    let startedAt: String
    let endedAt: String?
    let active: Bool
    let source: String
    let summary: WorkoutSummary?
    let commitCount: Int

    enum CodingKeys: String, CodingKey {
        case id, active, source, summary
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case commitCount = "commit_count"
    }

    var startDate: Date? {
        ISO8601DateFormatter().date(from: startedAt)
    }

    var endDate: Date? {
        guard let ended = endedAt else { return nil }
        return ISO8601DateFormatter().date(from: ended)
    }
}

struct SessionCommit: Codable, Identifiable {
    let id: String
    let repoOwner: String
    let repoName: String
    let commitSha: String
    let commitMsg: String
    let linesAdded: Int?
    let linesRemoved: Int?
    let committedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repoOwner = "repo_owner"
        case repoName = "repo_name"
        case commitSha = "commit_sha"
        case commitMsg = "commit_msg"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
        case committedAt = "committed_at"
    }

    var shortSha: String {
        String(commitSha.prefix(7))
    }

    var commitDate: Date? {
        ISO8601DateFormatter().date(from: committedAt)
    }
}

struct WorkoutSessionDetail: Codable, Identifiable {
    let id: String
    let startedAt: String
    let endedAt: String?
    let active: Bool
    let source: String
    let summary: WorkoutSummary?
    let commits: [SessionCommit]

    enum CodingKeys: String, CodingKey {
        case id, active, source, summary, commits
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct HRSample: Codable, Identifiable {
    let bpm: Int
    let ts: String

    var id: String { ts }

    var timestamp: Date? {
        ISO8601DateFormatter().date(from: ts)
    }
}

struct HRBucket: Codable, Identifiable {
    let bucketStart: String
    let bucketEnd: String
    let minBpm: Int
    let maxBpm: Int
    let avgBpm: Int
    let sampleCount: Int
    let timeAboveThresholdSecs: Int
    let thresholdBpm: Int

    var id: String { bucketStart }

    enum CodingKeys: String, CodingKey {
        case minBpm = "min_bpm"
        case maxBpm = "max_bpm"
        case avgBpm = "avg_bpm"
        case sampleCount = "sample_count"
        case timeAboveThresholdSecs = "time_above_threshold_secs"
        case thresholdBpm = "threshold_bpm"
        case bucketStart = "bucket_start"
        case bucketEnd = "bucket_end"
    }

    var startDate: Date? {
        ISO8601DateFormatter().date(from: bucketStart)
    }
}

struct SessionsListResponse: Codable {
    let sessions: [WorkoutSessionListItem]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case sessions
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct HRSamplesResponse: Codable {
    let samples: [HRSample]
}

struct HRBucketsResponse: Codable {
    let buckets: [HRBucket]
}

// MARK: - API Responses

struct ErrorResponse: Codable {
    let error: String
}

struct ThresholdUpdateResponse: Codable {
    let hrThresholdBpm: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case hrThresholdBpm = "hr_threshold_bpm"
        case updatedAt = "updated_at"
    }
}

struct InstallUrlResponse: Codable {
    let installUrl: String
    let owner: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case installUrl = "install_url"
        case owner, name
    }
}
