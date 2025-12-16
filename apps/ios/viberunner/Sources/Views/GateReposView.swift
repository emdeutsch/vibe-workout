import SwiftUI
import SafariServices
import os.log

private let logger = Logger(subsystem: "com.viberunner.app", category: "GateReposView")

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Safari View Controller Wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .systemBlue
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

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
                    Text("Sign in with GitHub to create repos")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Go to Settings → Sign Out, then sign back in with GitHub")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
    @State private var installURL: URL?

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
                            installURL = url
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You need to install the viberunner GitHub App on this repository to enable HR signal updates.")
        }
        .sheet(item: $installURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .onChange(of: installURL) { oldValue, newValue in
            // Refresh repos when Safari sheet closes
            if oldValue != nil && newValue == nil {
                Task {
                    try? await apiService.fetchGateRepos()
                }
            }
        }
    }
}

// MARK: - Create Sheet

struct CreateGateRepoSheet: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) var dismiss

    // Basic settings
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true

    // Owner (user or org)
    @State private var selectedOwner: String? = nil
    @State private var organizations: [GitHubOrg] = []
    @State private var isLoadingOrgs = false  // Org support disabled for launch

    // Templates
    @State private var selectedLicense: String? = nil
    @State private var selectedGitignore: String? = nil

    // Repository features
    @State private var hasIssues = true
    @State private var hasWiki = false      // Most projects don't use GitHub wikis
    @State private var hasProjects = false  // Most projects use external project management

    // Merge settings
    @State private var allowSquashMerge = true
    @State private var allowMergeCommit = true
    @State private var allowRebaseMerge = true
    @State private var deleteBranchOnMerge = true  // Keeps repo clean after PRs are merged

    // GitHub App
    @State private var autoInstallApp = true

    // Expandable sections
    @State private var showTemplateSettings = false
    @State private var showFeatureSettings = false
    @State private var showMergeSettings = false

    // State
    @State private var isCreating = false
    @State private var installURL: URL?
    @State private var error: String?
    @State private var createdRepo: CreateGateRepoResponse?

    // Common license options
    private let licenseOptions = [
        ("None", nil as String?),
        ("MIT License", "mit"),
        ("Apache License 2.0", "apache-2.0"),
        ("GNU GPLv3", "gpl-3.0"),
        ("BSD 3-Clause", "bsd-3-clause"),
        ("ISC License", "isc"),
        ("Mozilla Public License 2.0", "mpl-2.0"),
        ("The Unlicense", "unlicense"),
    ]

    // Common gitignore templates
    private let gitignoreOptions = [
        ("None", nil as String?),
        ("Node", "Node"),
        ("Swift", "Swift"),
        ("Python", "Python"),
        ("Go", "Go"),
        ("Rust", "Rust"),
        ("Java", "Java"),
        ("C++", "C++"),
        ("macOS", "macOS"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Basic Section
                Section {
                    TextField("Repository name", text: $name)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Description (optional)", text: $description)

                    // Owner picker - commented out for launch (requires read:org scope)
                    // TODO: Re-enable when ready to request read:org permission
                    /*
                    if isLoadingOrgs {
                        HStack {
                            Text("Owner")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Picker("Owner", selection: $selectedOwner) {
                            if let username = apiService.githubStatus?.username {
                                Text(username).tag(nil as String?)
                            }
                            ForEach(organizations) { org in
                                Text(org.login).tag(org.login as String?)
                            }
                        }
                    }
                    */
                }

                // Visibility Section
                Section {
                    Toggle("Private repository", isOn: $isPrivate)
                } footer: {
                    Text("Private repositories are only visible to you and collaborators.")
                }

                // Template Section (collapsible)
                Section {
                    DisclosureGroup("Templates", isExpanded: $showTemplateSettings) {
                        Picker("License", selection: $selectedLicense) {
                            ForEach(licenseOptions, id: \.1) { option in
                                Text(option.0).tag(option.1)
                            }
                        }

                        Picker(".gitignore", selection: $selectedGitignore) {
                            ForEach(gitignoreOptions, id: \.1) { option in
                                Text(option.0).tag(option.1)
                            }
                        }
                    }
                }

                // Features Section (collapsible)
                Section {
                    DisclosureGroup("Features", isExpanded: $showFeatureSettings) {
                        Toggle("Issues", isOn: $hasIssues)
                        Toggle("Wiki", isOn: $hasWiki)
                        Toggle("Projects", isOn: $hasProjects)
                    }
                }

                // Merge Settings Section (collapsible)
                Section {
                    DisclosureGroup("Merge Settings", isExpanded: $showMergeSettings) {
                        Toggle("Allow squash merging", isOn: $allowSquashMerge)
                        Toggle("Allow merge commits", isOn: $allowMergeCommit)
                        Toggle("Allow rebase merging", isOn: $allowRebaseMerge)
                        Toggle("Delete branch on merge", isOn: $deleteBranchOnMerge)
                    }
                }

                // GitHub App Section
                Section {
                    Toggle("Install viberunner app after creation", isOn: $autoInstallApp)
                } footer: {
                    Text("The viberunner GitHub App is required to update HR signals in your repository.")
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

                            if repo.needsAppInstall && repo.installUrl == nil {
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
            // .task {
            //     await loadOrganizations()
            // }
            .sheet(item: $installURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
            .onChange(of: installURL) { oldValue, newValue in
                // Auto-dismiss and refresh when Safari closes after repo creation
                if oldValue != nil && newValue == nil && createdRepo != nil {
                    Task {
                        try? await apiService.fetchGateRepos()
                    }
                    dismiss()
                }
            }
        }
    }

    private func loadOrganizations() async {
        isLoadingOrgs = true
        logger.info("Loading organizations...")
        do {
            organizations = try await apiService.fetchOrganizations()
            logger.info("Loaded \(self.organizations.count) organizations")
            for org in organizations {
                logger.debug("Org: \(org.login)")
            }
        } catch {
            logger.error("Failed to load organizations: \(error.localizedDescription)")
        }
        isLoadingOrgs = false
    }

    private func createRepo() async {
        isCreating = true
        error = nil

        do {
            var params = APIService.CreateGateRepoParams(name: name)
            params.description = description.isEmpty ? nil : description
            params.isPrivate = isPrivate
            params.org = selectedOwner
            params.hasIssues = hasIssues
            params.hasWiki = hasWiki
            params.hasProjects = hasProjects
            params.licenseTemplate = selectedLicense
            params.gitignoreTemplate = selectedGitignore
            params.allowSquashMerge = allowSquashMerge
            params.allowMergeCommit = allowMergeCommit
            params.allowRebaseMerge = allowRebaseMerge
            params.deleteBranchOnMerge = deleteBranchOnMerge
            params.autoInstallApp = autoInstallApp

            let repo = try await apiService.createGateRepo(params: params)
            createdRepo = repo

            // Auto-open GitHub App installation if URL is provided
            if let installUrlString = repo.installUrl,
               let url = URL(string: installUrlString) {
                installURL = url
            }
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
