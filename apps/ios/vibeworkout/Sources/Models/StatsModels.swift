import Foundation

// MARK: - Time Period

enum TimePeriod: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all = "all"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "1Y"
        case .all: return "All"
        }
    }

    var fullName: String {
        switch self {
        case .week: return "Last 7 Days"
        case .month: return "Last 30 Days"
        case .quarter: return "Last 90 Days"
        case .year: return "Last Year"
        case .all: return "All Time"
        }
    }
}

// MARK: - Date Parsing Helper

private func parseISO8601Date(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

// MARK: - Overview Stats

struct OverviewStats: Codable {
    let period: String
    let periodStart: String
    let periodEnd: String
    let workout: WorkoutAggregateStats
    let coding: CodingAggregateStats
    let tools: ToolAggregateStats
    let chart: ActivityChartData

    var periodStartDate: Date? {
        parseISO8601Date(periodStart)
    }

    var periodEndDate: Date? {
        parseISO8601Date(periodEnd)
    }
}

struct WorkoutAggregateStats: Codable {
    let totalDurationSecs: Int
    let sessionCount: Int
    let avgBpm: Int
    let maxBpm: Int
    let minBpm: Int
    let timeAboveThresholdSecs: Int
    let timeBelowThresholdSecs: Int

    var formattedDuration: String {
        let hours = totalDurationSecs / 3600
        let minutes = (totalDurationSecs % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var thresholdPercentage: Double {
        let total = timeAboveThresholdSecs + timeBelowThresholdSecs
        guard total > 0 else { return 0 }
        return Double(timeAboveThresholdSecs) / Double(total)
    }
}

struct CodingAggregateStats: Codable {
    let totalCommits: Int
    let linesAdded: Int
    let linesRemoved: Int
    let prsOpened: Int
    let prsMerged: Int
    let prsClosed: Int
    let reposCount: Int?
    let filesChanged: Int?

    var totalPrs: Int {
        prsOpened + prsMerged + prsClosed
    }

    var formattedLinesAdded: String {
        if linesAdded >= 1000 {
            return String(format: "%.1fk", Double(linesAdded) / 1000.0)
        }
        return "\(linesAdded)"
    }

    var formattedLinesRemoved: String {
        if linesRemoved >= 1000 {
            return String(format: "%.1fk", Double(linesRemoved) / 1000.0)
        }
        return "\(linesRemoved)"
    }
}

struct ToolAggregateStats: Codable {
    let totalAttempts: Int
    let allowed: Int
    let blocked: Int
    let succeeded: Int?
    let failed: Int?
    let successRate: Double
    let topTools: [ToolCount]?

    var formattedSuccessRate: String {
        String(format: "%.0f%%", successRate * 100)
    }

    var allowedPercentage: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(allowed) / Double(totalAttempts)
    }
}

struct ToolCount: Codable, Identifiable {
    let name: String
    let count: Int

    var id: String { name }
}

// MARK: - Activity Chart

struct ActivityChartData: Codable {
    let buckets: [ActivityBucket]
}

struct ActivityBucket: Codable, Identifiable {
    let date: String
    let durationSecs: Int
    let commits: Int
    let linesAdded: Int
    let linesRemoved: Int
    let toolCalls: Int?

    var id: String { date }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    var formattedDate: String {
        guard let parsed = parsedDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: parsed)
    }
}

// MARK: - Project Stats

struct ProjectStats: Codable, Identifiable {
    let repoFullName: String
    let repoOwner: String
    let repoName: String
    let lastActiveAt: String
    let workout: WorkoutAggregateStats
    let coding: CodingAggregateStats
    let tools: ToolAggregateStats

    var id: String { repoFullName }

    var lastActiveDate: Date? {
        parseISO8601Date(lastActiveAt)
    }

    var formattedLastActive: String {
        guard let date = lastActiveDate else { return lastActiveAt }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ProjectsListResponse: Codable {
    let projects: [ProjectStats]
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - Project Detail

struct ProjectDetail: Codable {
    let repoFullName: String
    let repoOwner: String
    let repoName: String
    let htmlUrl: String?
    let lastActiveAt: String?
    let workout: WorkoutAggregateStats
    let coding: CodingAggregateStats
    let tools: ToolAggregateStats
    let chart: ActivityChartData
    let recentSessions: [ProjectSessionSummary]
    let hasMoreSessions: Bool
    let sessionsCursor: String?

    var lastActiveDate: Date? {
        guard let lastActiveAt = lastActiveAt else { return nil }
        return parseISO8601Date(lastActiveAt)
    }
}

struct ProjectSessionSummary: Codable, Identifiable {
    let id: String
    let startedAt: String
    let endedAt: String?
    let durationSecs: Int
    let avgBpm: Int
    let maxBpm: Int
    let commits: Int
    let linesAdded: Int
    let linesRemoved: Int

    var startDate: Date? {
        parseISO8601Date(startedAt)
    }

    var endDate: Date? {
        guard let endedAt = endedAt else { return nil }
        return parseISO8601Date(endedAt)
    }

    var formattedDuration: String {
        let hours = durationSecs / 3600
        let minutes = (durationSecs % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedDate: String {
        guard let date = startDate else { return startedAt }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ProjectSessionsResponse: Codable {
    let sessions: [ProjectSessionSummary]
    let hasMore: Bool
    let nextCursor: String?
}
