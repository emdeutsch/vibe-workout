import SwiftUI
import Charts

struct WorkoutHistoryCard: View {
    let session: WorkoutSessionListItem

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header row: date + duration
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let date = session.startDate {
                        Text(dateFormatter.string(from: date))
                            .font(.subheadline.weight(.medium))
                    }

                    if session.active {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                if let summary = session.summary {
                    Text(summary.formattedDuration)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }

            // Middle: Sparkline + HR stats
            HStack(spacing: Spacing.lg) {
                // Sparkline
                if let bpms = session.sparklineBpms, !bpms.isEmpty {
                    HeartRateSparklineView(
                        dataPoints: bpms.toChartPoints(),
                        thresholdBpm: session.summary?.thresholdBpm ?? 100
                    )
                    .frame(width: 100, height: 40)
                }

                Spacer()

                // HR Stats
                if let summary = session.summary {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("\(summary.avgBpm) avg")
                                .font(.subheadline.monospacedDigit())
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(summary.maxBpm) max")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Bottom: Code stats + repos
            HStack {
                // Lines changed
                if let added = session.totalLinesAdded, let removed = session.totalLinesRemoved,
                   added > 0 || removed > 0 {
                    HStack(spacing: Spacing.sm) {
                        Text("+\(added)")
                            .foregroundStyle(.green)
                        Text("-\(removed)")
                            .foregroundStyle(.red)
                    }
                    .font(.caption.monospacedDigit())
                } else if session.commitCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                        Text("\(session.commitCount) commits")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Repo chips
                if let repoNames = session.repoNames, !repoNames.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ForEach(Array(repoNames.prefix(2)), id: \.self) { name in
                            RepoChip(name: name)
                        }
                        if repoNames.count > 2 {
                            Text("+\(repoNames.count - 2)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Repo Chip

struct RepoChip: View {
    let name: String

    private var shortName: String {
        // If it's "owner/repo", just show "repo"
        if let slashIndex = name.lastIndex(of: "/") {
            return String(name[name.index(after: slashIndex)...])
        }
        return name
    }

    var body: some View {
        Text(shortName)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        WorkoutHistoryCard(
            session: WorkoutSessionListItem(
                id: "1",
                startedAt: ISO8601DateFormatter().string(from: Date()),
                endedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                active: false,
                source: "watch",
                summary: WorkoutSummary(
                    durationSecs: 3600,
                    avgBpm: 112,
                    maxBpm: 145,
                    minBpm: 85,
                    timeAboveThresholdSecs: 2700,
                    timeBelowThresholdSecs: 900,
                    thresholdBpm: 100,
                    totalSamples: 180
                ),
                commitCount: 12,
                totalLinesAdded: 543,
                totalLinesRemoved: 127,
                topRepo: "owner/my-repo",
                repoNames: ["owner/repo-one", "owner/repo-two", "owner/repo-three"],
                sparklineBpms: [95, 102, 110, 115, 120, 118, 125, 130, 128, 122, 118, 115, 110, 108, 105]
            )
        )

        WorkoutHistoryCard(
            session: WorkoutSessionListItem(
                id: "2",
                startedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)),
                endedAt: nil,
                active: true,
                source: "watch",
                summary: WorkoutSummary(
                    durationSecs: 1800,
                    avgBpm: 98,
                    maxBpm: 120,
                    minBpm: 75,
                    timeAboveThresholdSecs: 900,
                    timeBelowThresholdSecs: 900,
                    thresholdBpm: 100,
                    totalSamples: 90
                ),
                commitCount: 3,
                totalLinesAdded: 45,
                totalLinesRemoved: 12,
                topRepo: nil,
                repoNames: ["owner/current-repo"],
                sparklineBpms: [88, 92, 95, 98, 102, 105, 108, 105, 100, 97]
            )
        )
    }
    .padding()
}
