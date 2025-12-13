import SwiftUI

struct GateReposView: View {
    @EnvironmentObject var apiService: APIService

    @State private var isLoading = false
    @State private var showingCreateSheet = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if apiService.gateRepos.isEmpty && !isLoading {
                    EmptyReposView(showingCreateSheet: $showingCreateSheet)
                } else {
                    List {
                        ForEach(apiService.gateRepos) { repo in
                            GateRepoRow(repo: repo)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task {
                                            try? await apiService.deleteGateRepo(id: repo.id)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        Task {
                                            try? await apiService.toggleGateRepo(id: repo.id, active: !repo.active)
                                        }
                                    } label: {
                                        Label(repo.active ? "Disable" : "Enable",
                                              systemImage: repo.active ? "pause" : "play")
                                    }
                                    .tint(repo.active ? .orange : .green)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Gate Repos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(apiService.githubStatus?.connected != true)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .task {
                await refresh()
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGateRepoSheet()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func refresh() async {
        isLoading = true
        do {
            _ = try await apiService.fetchGateRepos()
            _ = try await apiService.fetchGitHubStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isLoading = false
    }
}

// MARK: - Empty State

struct EmptyReposView: View {
    @Binding var showingCreateSheet: Bool
    @EnvironmentObject var apiService: APIService

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Gate Repos")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Create a gate repo to enable HR-gated Claude Code tools")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if apiService.githubStatus?.connected == true {
                Button {
                    showingCreateSheet = true
                } label: {
                    Text("Create Gate Repo")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            } else {
                VStack(spacing: 12) {
                    Text("Connect GitHub to create repos")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    NavigationLink("Go to Settings") {
                        SettingsView()
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Repo Row

struct GateRepoRow: View {
    let repo: GateRepo
    @EnvironmentObject var apiService: APIService

    @State private var showingInstallAlert = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(repo.active && repo.githubAppInstalled ? .green : .orange)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(repo.fullName)
                    .font(.headline)

                HStack(spacing: 8) {
                    if !repo.githubAppInstalled {
                        Label("App not installed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if !repo.active {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if !repo.githubAppInstalled {
                Button("Install App") {
                    showingInstallAlert = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .alert("Install GitHub App", isPresented: $showingInstallAlert) {
            Button("Open GitHub") {
                Task {
                    if let response = try? await apiService.getGateRepoInstallURL(id: repo.id),
                       let url = URL(string: response.installUrl) {
                        await MainActor.run {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You need to install the viberunner GitHub App on this repository to enable HR signal updates.")
        }
    }
}

// MARK: - Create Sheet

struct CreateGateRepoSheet: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true
    @State private var isCreating = false
    @State private var error: String?
    @State private var createdRepo: CreateGateRepoResponse?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Repository name", text: $name)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Description (optional)", text: $description)

                    Toggle("Private repository", isOn: $isPrivate)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                if let repo = createdRepo {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Repository created!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            Text(repo.htmlUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if repo.needsAppInstall {
                                Text("Install the viberunner GitHub App to enable HR gating.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Gate Repo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if createdRepo != nil {
                        Button("Done") {
                            dismiss()
                        }
                    } else {
                        Button("Create") {
                            Task {
                                await createRepo()
                            }
                        }
                        .disabled(name.isEmpty || isCreating)
                    }
                }
            }
            .overlay {
                if isCreating {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func createRepo() async {
        isCreating = true
        error = nil

        do {
            let repo = try await apiService.createGateRepo(
                name: name,
                description: description.isEmpty ? nil : description,
                isPrivate: isPrivate
            )
            createdRepo = repo
        } catch {
            self.error = error.localizedDescription
        }

        isCreating = false
    }
}

#Preview {
    GateReposView()
        .environmentObject(APIService.shared)
}
