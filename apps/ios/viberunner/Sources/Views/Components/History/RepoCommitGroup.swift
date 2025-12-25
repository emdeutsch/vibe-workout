import SwiftUI

struct RepoCommitGroup: View {
    let repoName: String
    let commits: [SessionCommit]
    @State private var isExpanded = true

    private var totalAdded: Int {
        commits.compactMap { $0.linesAdded }.reduce(0, +)
    }

    private var totalRemoved: Int {
        commits.compactMap { $0.linesRemoved }.reduce(0, +)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                ForEach(commits) { commit in
                    CommitRowView(commit: commit)

                    if commit.id != commits.last?.id {
                        Divider()
                            .padding(.leading, Spacing.xl)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)

                Text(repoName)
                    .font(.subheadline.weight(.medium))

                Spacer()

                HStack(spacing: Spacing.sm) {
                    Text("+\(totalAdded)")
                        .foregroundStyle(.green)
                    Text("-\(totalRemoved)")
                        .foregroundStyle(.red)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct CommitRowView: View {
    let commit: SessionCommit

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // SHA and timestamp
            HStack {
                Text(commit.shortSha)
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)

                Spacer()

                if let date = commit.commitDate {
                    Text(dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Commit message
            Text(commit.commitMsg)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Lines changed
            if let added = commit.linesAdded, let removed = commit.linesRemoved {
                HStack(spacing: Spacing.sm) {
                    Text("+\(added)")
                        .foregroundStyle(.green)
                    Text("-\(removed)")
                        .foregroundStyle(.red)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.leading, Spacing.lg)
    }
}

#Preview {
    List {
        RepoCommitGroup(
            repoName: "owner/my-repo",
            commits: [
                SessionCommit(
                    id: "1",
                    repoOwner: "owner",
                    repoName: "my-repo",
                    commitSha: "abc123def456789",
                    commitMsg: "Add new feature for user authentication",
                    linesAdded: 145,
                    linesRemoved: 23,
                    committedAt: ISO8601DateFormatter().string(from: Date())
                ),
                SessionCommit(
                    id: "2",
                    repoOwner: "owner",
                    repoName: "my-repo",
                    commitSha: "def456abc789012",
                    commitMsg: "Fix bug in login flow that was causing crashes on iOS 17",
                    linesAdded: 12,
                    linesRemoved: 45,
                    committedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
                )
            ]
        )
    }
}
