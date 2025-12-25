import SwiftUI

struct ActiveReposSection: View {
    let repos: [SelectedRepo]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Active Repos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(repos) { repo in
                        RepoChip(name: repo.name)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Repo Chip

struct RepoChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(Color.hrAboveThreshold.opacity(0.12))
            )
            .foregroundStyle(Color.hrAboveThreshold)
    }
}

#Preview {
    ActiveReposSection(repos: [
        SelectedRepo(id: "1", owner: "user", name: "repo-one"),
        SelectedRepo(id: "2", owner: "user", name: "another-repo"),
        SelectedRepo(id: "3", owner: "user", name: "third-repository"),
        SelectedRepo(id: "4", owner: "user", name: "fourth-one"),
        SelectedRepo(id: "5", owner: "user", name: "fifth-repo")
    ])
    .padding()
}
