# Aggregated Workout History Feature Spec

## Overview

Add aggregated historical views to the app allowing users to see their total workout and coding progress over time, both overall and per-project/repository.

## Navigation Structure

### Approach: Segmented Activity Tab

Rename the current "History" tab to **"Activity"** and add a segmented control with three views:

```
┌─────────────────────────────────────────┐
│              Activity                    │
├─────────────────────────────────────────┤
│  [Overview]  [Projects]  [Sessions]     │
└─────────────────────────────────────────┘
```

| Segment | Purpose |
|---------|---------|
| **Overview** | Aggregated dashboard with time-period selector showing combined workout + coding stats |
| **Projects** | List of repositories with per-project aggregated stats |
| **Sessions** | Existing individual workout session list (current HistoryView) |

**Rationale:**
- Keeps tab count at 4 (iOS HIG recommends ≤5)
- Groups all historical/retrospective data in one logical place
- Preserves existing workflow - "Sessions" segment is the current behavior
- Natural discovery - users see new capabilities immediately

---

## View Specifications

### 1. Overview Segment (Dashboard)

**Purpose:** Show aggregated stats across all workouts for a selected time period.

#### Time Period Selector
Pill-style selector at the top:
```
[7D] [30D] [90D] [1Y] [All]
```
- 7D = Last 7 days
- 30D = Last 30 days
- 90D = Last 90 days
- 1Y = Last year
- All = All time

#### Stats Cards

**Workout Stats Card:**
| Metric | Description |
|--------|-------------|
| Total Workout Time | Sum of all session durations |
| Sessions | Count of workout sessions |
| Avg Heart Rate | Weighted average across sessions |
| Max Heart Rate | Highest recorded across all sessions |
| Time Above Threshold | Total time spent above HR threshold |
| Time Below Threshold | Total time spent below HR threshold |

**Coding Stats Card:**
| Metric | Description |
|--------|-------------|
| Total Commits | Count of commits across all sessions |
| Lines Added | Sum of lines added |
| Lines Removed | Sum of lines removed |
| Pull Requests | Count of PRs (opened/merged/closed breakdown) |
| Repos Touched | Count of unique repositories |

**Tool Usage Stats Card:**
| Metric | Description |
|--------|-------------|
| Total Tool Calls | Count of all tool attempts |
| Allowed | Tool calls that proceeded (HR above threshold) |
| Blocked | Tool calls blocked due to low HR |
| Success Rate | % of allowed tools that succeeded |
| Top Tools | Most frequently used tools |

#### Activity Chart
- Bar chart showing daily/weekly activity over the selected period
- Toggle between: Workout Time | Commits | Lines of Code | Tool Calls
- X-axis: Time buckets (days for 7D/30D, weeks for 90D/1Y)
- Y-axis: Selected metric value

#### Quick Links
- "View all projects →" link to Projects segment
- "View all sessions →" link to Sessions segment

---

### 2. Projects Segment

**Purpose:** List all repositories with aggregated stats, allowing drill-down into individual project details.

#### Project List
Sorted by: Most recent activity (default), or toggle to sort by total time/commits.

Each project card shows:
```
┌─────────────────────────────────────────┐
│ 📁 owner/repo-name                      │
├─────────────────────────────────────────┤
│ ⏱ 12h 34m    ❤️ 142 avg    📈 156 max  │
│ 📝 47 commits  +1,234 / -567 lines      │
│ 🔀 3 PRs      📅 Last active: 2 days ago│
└─────────────────────────────────────────┘
```

**Metrics per project:**

| Workout Stats | Coding Stats | Tool Stats |
|---------------|--------------|------------|
| Total workout time | Total commits | Total tool calls |
| Number of sessions | Lines added/removed | Allowed / Blocked |
| Avg HR (weighted) | PRs opened/merged | Success rate |
| Max HR | Files changed | Top tools used |
| Time above/below threshold | | |

#### Project Detail View (on tap)

Full-screen detail view for a single repository:

**Header:**
- Repository name + GitHub link
- Last active date
- Total sessions count

**Workout Stats Section:**
- Total time spent on this project
- Number of sessions
- Avg/Max/Min HR while working on this project
- Time above/below threshold
- HR trend chart (optional: avg HR over time for this project)

**Coding Stats Section:**
- Total commits
- Total lines added/removed
- PRs opened/merged/closed
- Top contributors (if applicable)
- Activity chart (commits over time)

**Sessions List:**
- Paginated list of all sessions that touched this repo
- Tapping a session navigates to existing WorkoutDetailView
- Shows: Date, duration, HR stats, lines changed for that session

---

### 3. Sessions Segment

**Purpose:** Individual workout session list (existing functionality).

This is the current `HistoryView` implementation - no changes needed. Just relocate it as a segment within the Activity tab.

---

## API Endpoints

### New Endpoints Required

#### `GET /api/workout/stats/overview`
Aggregated stats for the dashboard.

**Query Parameters:**
- `period`: `7d` | `30d` | `90d` | `1y` | `all` (default: `30d`)

**Response:**
```json
{
  "period": "30d",
  "periodStart": "2025-11-29T00:00:00Z",
  "periodEnd": "2025-12-29T00:00:00Z",
  "workout": {
    "totalDurationSecs": 45000,
    "sessionCount": 15,
    "avgBpm": 142,
    "maxBpm": 178,
    "minBpm": 95,
    "timeAboveThresholdSecs": 32000,
    "timeBelowThresholdSecs": 13000
  },
  "coding": {
    "totalCommits": 87,
    "linesAdded": 4523,
    "linesRemoved": 1876,
    "prsOpened": 5,
    "prsMerged": 4,
    "prsClosed": 1,
    "reposCount": 6
  },
  "tools": {
    "totalAttempts": 1250,
    "allowed": 1180,
    "blocked": 70,
    "succeeded": 1150,
    "failed": 30,
    "successRate": 0.97,
    "topTools": [
      { "name": "Read", "count": 450 },
      { "name": "Edit", "count": 320 },
      { "name": "Bash", "count": 280 }
    ]
  },
  "chart": {
    "buckets": [
      {
        "date": "2025-12-01",
        "durationSecs": 3600,
        "commits": 5,
        "linesAdded": 234,
        "linesRemoved": 87,
        "toolCalls": 45
      }
      // ... one entry per day/week depending on period
    ]
  }
}
```

#### `GET /api/workout/stats/projects`
List of projects with aggregated stats.

**Query Parameters:**
- `period`: `7d` | `30d` | `90d` | `1y` | `all` (default: `all`)
- `sort`: `recent` | `time` | `commits` (default: `recent`)
- `cursor`: pagination cursor
- `limit`: number of results (default: 20)

**Response:**
```json
{
  "projects": [
    {
      "repoFullName": "owner/repo",
      "repoOwner": "owner",
      "repoName": "repo",
      "lastActiveAt": "2025-12-27T15:30:00Z",
      "workout": {
        "totalDurationSecs": 14400,
        "sessionCount": 5,
        "avgBpm": 138,
        "maxBpm": 165,
        "timeAboveThresholdSecs": 10000,
        "timeBelowThresholdSecs": 4400
      },
      "coding": {
        "totalCommits": 23,
        "linesAdded": 1456,
        "linesRemoved": 432,
        "prsOpened": 2,
        "prsMerged": 2,
        "prsClosed": 0
      },
      "tools": {
        "totalAttempts": 340,
        "allowed": 320,
        "blocked": 20,
        "successRate": 0.95
      }
    }
  ],
  "hasMore": true,
  "nextCursor": "abc123"
}
```

#### `GET /api/workout/stats/projects/:repoFullName`
Detailed stats for a single project.

**Path Parameters:**
- `repoFullName`: URL-encoded repo full name (e.g., `owner%2Frepo`)

**Query Parameters:**
- `period`: `7d` | `30d` | `90d` | `1y` | `all` (default: `all`)

**Response:**
```json
{
  "repoFullName": "owner/repo",
  "repoOwner": "owner",
  "repoName": "repo",
  "htmlUrl": "https://github.com/owner/repo",
  "lastActiveAt": "2025-12-27T15:30:00Z",
  "workout": {
    "totalDurationSecs": 14400,
    "sessionCount": 5,
    "avgBpm": 138,
    "maxBpm": 165,
    "minBpm": 98,
    "timeAboveThresholdSecs": 10000,
    "timeBelowThresholdSecs": 4400
  },
  "coding": {
    "totalCommits": 23,
    "linesAdded": 1456,
    "linesRemoved": 432,
    "prsOpened": 2,
    "prsMerged": 2,
    "prsClosed": 0,
    "filesChanged": 45
  },
  "tools": {
    "totalAttempts": 340,
    "allowed": 320,
    "blocked": 20,
    "succeeded": 310,
    "failed": 10,
    "successRate": 0.97,
    "topTools": [
      { "name": "Read", "count": 120 },
      { "name": "Edit", "count": 95 },
      { "name": "Bash", "count": 80 }
    ]
  },
  "chart": {
    "buckets": [
      {
        "date": "2025-12-01",
        "durationSecs": 3600,
        "commits": 5,
        "linesAdded": 234,
        "linesRemoved": 87
      }
    ]
  },
  "recentSessions": [
    {
      "id": "session-uuid",
      "startedAt": "2025-12-27T14:00:00Z",
      "endedAt": "2025-12-27T15:30:00Z",
      "durationSecs": 5400,
      "avgBpm": 140,
      "maxBpm": 165,
      "commits": 8,
      "linesAdded": 456,
      "linesRemoved": 123
    }
  ],
  "hasMoreSessions": true,
  "sessionsCursor": "xyz789"
}
```

#### `GET /api/workout/stats/projects/:repoFullName/sessions`
Paginated sessions for a specific project.

**Path Parameters:**
- `repoFullName`: URL-encoded repo full name

**Query Parameters:**
- `cursor`: pagination cursor
- `limit`: number of results (default: 20)

**Response:**
```json
{
  "sessions": [
    {
      "id": "session-uuid",
      "startedAt": "2025-12-27T14:00:00Z",
      "endedAt": "2025-12-27T15:30:00Z",
      "durationSecs": 5400,
      "avgBpm": 140,
      "maxBpm": 165,
      "minBpm": 102,
      "commits": 8,
      "linesAdded": 456,
      "linesRemoved": 123,
      "prs": 1
    }
  ],
  "hasMore": true,
  "nextCursor": "abc123"
}
```

---

## iOS Implementation

### New Files

| File | Purpose |
|------|---------|
| `Sources/Views/ActivityView.swift` | Container with segmented control |
| `Sources/Views/Activity/OverviewView.swift` | Dashboard/overview segment |
| `Sources/Views/Activity/ProjectsListView.swift` | Projects list segment |
| `Sources/Views/Activity/ProjectDetailView.swift` | Individual project detail |
| `Sources/Views/Components/Activity/StatsCard.swift` | Reusable stats card component |
| `Sources/Views/Components/Activity/ActivityChart.swift` | Bar chart for activity trends |
| `Sources/Views/Components/Activity/ProjectCard.swift` | Project list item card |
| `Sources/Views/Components/Activity/TimePeriodPicker.swift` | Period selector pills |
| `Sources/Models/StatsModels.swift` | Data models for stats responses |
| `Sources/Services/APIService+Stats.swift` | API service extension for stats endpoints |

### Modified Files

| File | Change |
|------|--------|
| `Sources/App/MainTabView.swift` | Rename History → Activity, update icon |
| `Sources/Views/HistoryView.swift` | Move to `Sources/Views/Activity/SessionsView.swift` |

### Data Models

```swift
// StatsModels.swift

struct OverviewStats: Codable {
    let period: String
    let periodStart: Date
    let periodEnd: Date
    let workout: WorkoutAggregateStats
    let coding: CodingAggregateStats
    let tools: ToolAggregateStats
    let chart: ActivityChartData
}

struct WorkoutAggregateStats: Codable {
    let totalDurationSecs: Int
    let sessionCount: Int
    let avgBpm: Int
    let maxBpm: Int
    let minBpm: Int?
    let timeAboveThresholdSecs: Int
    let timeBelowThresholdSecs: Int
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
}

struct ToolAggregateStats: Codable {
    let totalAttempts: Int
    let allowed: Int
    let blocked: Int
    let succeeded: Int?
    let failed: Int?
    let successRate: Double
    let topTools: [ToolCount]?
}

struct ToolCount: Codable, Identifiable {
    let name: String
    let count: Int

    var id: String { name }
}

struct ActivityChartData: Codable {
    let buckets: [ActivityBucket]
}

struct ActivityBucket: Codable, Identifiable {
    let date: String
    let durationSecs: Int
    let commits: Int
    let linesAdded: Int
    let linesRemoved: Int
    let toolCalls: Int

    var id: String { date }
}

struct ProjectStats: Codable, Identifiable {
    let repoFullName: String
    let repoOwner: String
    let repoName: String
    let lastActiveAt: Date
    let workout: WorkoutAggregateStats
    let coding: CodingAggregateStats
    let tools: ToolAggregateStats

    var id: String { repoFullName }
}

struct ProjectDetail: Codable {
    let repoFullName: String
    let repoOwner: String
    let repoName: String
    let htmlUrl: String?
    let lastActiveAt: Date
    let workout: WorkoutAggregateStats
    let coding: CodingAggregateStats
    let tools: ToolAggregateStats
    let chart: ActivityChartData
    let recentSessions: [ProjectSessionSummary]
    let hasMoreSessions: Bool
    let sessionsCursor: String?
}

struct ProjectSessionSummary: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let durationSecs: Int
    let avgBpm: Int
    let maxBpm: Int
    let commits: Int
    let linesAdded: Int
    let linesRemoved: Int
}

enum TimePeriod: String, CaseIterable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "1y"
    case all = "all"

    var displayName: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "1Y"
        case .all: return "All"
        }
    }
}
```

---

## Database Queries

The API endpoints will need efficient queries. Key considerations:

### Overview Stats Query
```sql
-- Workout stats for period
SELECT
    COUNT(DISTINCT ws.id) as session_count,
    SUM(wsum.duration_secs) as total_duration,
    AVG(wsum.avg_bpm) as avg_bpm,  -- Note: should be weighted by duration
    MAX(wsum.max_bpm) as max_bpm,
    MIN(wsum.min_bpm) as min_bpm,
    SUM(wsum.time_above_threshold_secs) as time_above,
    SUM(wsum.time_below_threshold_secs) as time_below
FROM workout_sessions ws
JOIN workout_summaries wsum ON ws.id = wsum.session_id
WHERE ws.user_id = $userId
    AND ws.started_at >= $periodStart
    AND ws.ended_at IS NOT NULL;

-- Coding stats for period
SELECT
    COUNT(sc.id) as total_commits,
    SUM(sc.lines_added) as lines_added,
    SUM(sc.lines_removed) as lines_removed,
    COUNT(DISTINCT sc.repo_full_name) as repos_count
FROM session_commits sc
JOIN workout_sessions ws ON sc.session_id = ws.id
WHERE ws.user_id = $userId
    AND ws.started_at >= $periodStart;

-- Tool stats for period
SELECT
    COUNT(*) as total_attempts,
    SUM(CASE WHEN allowed THEN 1 ELSE 0 END) as allowed,
    SUM(CASE WHEN NOT allowed THEN 1 ELSE 0 END) as blocked,
    SUM(CASE WHEN succeeded = true THEN 1 ELSE 0 END) as succeeded,
    SUM(CASE WHEN succeeded = false THEN 1 ELSE 0 END) as failed
FROM tool_attempts ta
JOIN workout_sessions ws ON ta.session_id = ws.id
WHERE ws.user_id = $userId
    AND ws.started_at >= $periodStart;

-- Top tools for period
SELECT
    tool_name,
    COUNT(*) as count
FROM tool_attempts ta
JOIN workout_sessions ws ON ta.session_id = ws.id
WHERE ws.user_id = $userId
    AND ws.started_at >= $periodStart
GROUP BY tool_name
ORDER BY count DESC
LIMIT 5;
```

### Project Stats Query
```sql
-- Per-project aggregation
SELECT
    sc.repo_full_name,
    MAX(ws.started_at) as last_active,
    COUNT(DISTINCT ws.id) as session_count,
    SUM(wsum.duration_secs) as total_duration,
    -- ... other aggregates
FROM session_commits sc
JOIN workout_sessions ws ON sc.session_id = ws.id
JOIN workout_summaries wsum ON ws.id = wsum.session_id
WHERE ws.user_id = $userId
GROUP BY sc.repo_full_name
ORDER BY last_active DESC;
```

### Performance Considerations
- Add indexes on `session_commits.repo_full_name`
- Consider materialized views or caching for frequently-accessed aggregations
- Use cursor-based pagination for large result sets
- Implement response caching with short TTL (1-5 minutes)

---

## Implementation Order

### Phase 1: Backend API
1. Add new API routes in `services/api/src/routes/workout.ts`
2. Implement aggregation queries with proper indexing
3. Add tests for new endpoints

### Phase 2: iOS Data Layer
1. Create `StatsModels.swift` with new data models
2. Add API methods in `APIService+Stats.swift`
3. Test API integration

### Phase 3: iOS UI - Overview
1. Create `ActivityView.swift` with segmented control
2. Implement `OverviewView.swift` with stats cards
3. Create `TimePeriodPicker.swift` component
4. Implement `ActivityChart.swift` using SwiftUI Charts

### Phase 4: iOS UI - Projects
1. Create `ProjectsListView.swift`
2. Create `ProjectCard.swift` component
3. Implement `ProjectDetailView.swift`
4. Add navigation from project list to detail

### Phase 5: Integration & Polish
1. Move existing `HistoryView` to Sessions segment
2. Update `MainTabView.swift` (rename tab, update icon)
3. Add loading states and error handling
4. Implement pull-to-refresh
5. Test full flow end-to-end

---

## Open Questions

1. **Caching strategy** - Should we cache aggregated stats on the server, or compute on-demand?
2. **Empty states** - What to show when a project has no commits but has HR data?
3. **Time zone handling** - Should period boundaries be in user's local time or UTC?
4. **Chart interactions** - Should tapping a chart bar navigate to sessions from that day?

---

## Future Enhancements (Out of Scope)

- Streak tracking and achievements
- Goals and milestones
- Comparative analytics ("your best week")
- Export/sharing features
- Filtering sessions by HR metrics
- Search functionality
