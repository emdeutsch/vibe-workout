import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var watchConnectivity: WatchConnectivityService

    @State private var threshold: Double = Double(Config.defaultHRThreshold)
    @State private var isUpdatingThreshold = false
    @State private var showingSignOutAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Profile Section
                Section("Profile") {
                    if let user = authService.currentUser {
                        LabeledContent("Email", value: user.email ?? "Unknown")
                    }

                    if let profile = apiService.profile {
                        LabeledContent("User ID", value: String(profile.userId.prefix(8)) + "...")
                    }
                }

                // HR Threshold Section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("HR Threshold")
                            Spacer()
                            Text("\(Int(threshold)) BPM")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }

                        Slider(
                            value: $threshold,
                            in: Double(Config.minHRThreshold)...Double(Config.maxHRThreshold),
                            step: 5
                        ) {
                            Text("HR Threshold")
                        } minimumValueLabel: {
                            Text("\(Config.minHRThreshold)")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("\(Config.maxHRThreshold)")
                                .font(.caption)
                        }
                        .disabled(isUpdatingThreshold)
                        .onChange(of: threshold) { _, newValue in
                            updateThreshold(Int(newValue))
                        }
                    }
                } header: {
                    Text("Heart Rate")
                } footer: {
                    Text("Claude Code tools will be locked when your heart rate is below this threshold.")
                }

                // GitHub Section
                Section {
                    if let github = apiService.githubStatus, github.connected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            VStack(alignment: .leading) {
                                Text("Connected")
                                    .fontWeight(.medium)

                                if let username = github.username {
                                    Text("@\(username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Disconnect", role: .destructive) {
                                Task {
                                    try? await apiService.disconnectGitHub()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Not Connected")
                                    .fontWeight(.medium)

                                Text("Sign out and sign in with GitHub to connect")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("GitHub")
                } footer: {
                    Text("GitHub is connected automatically when you sign in with GitHub. This enables creating and managing gate repos.")
                }

                // Watch Section
                Section("Apple Watch") {
                    HStack {
                        Text("Watch App")
                        Spacer()
                        if watchConnectivity.isWatchAppInstalled {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Text("Not Installed")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Connection")
                        Spacer()
                        if watchConnectivity.isReachable {
                            Label("Connected", systemImage: "wifi")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Text("Not Connected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Account Section
                Section {
                    Button("Sign Out", role: .destructive) {
                        showingSignOutAlert = true
                    }
                }

                // About Section
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    Link("Documentation", destination: URL(string: "https://github.com/viberunner/viberunner")!)
                    Link("Report Issue", destination: URL(string: "https://github.com/viberunner/viberunner/issues")!)
                }
            }
            .navigationTitle("Settings")
            .task {
                // Fetch profile and GitHub status
                if let profile = try? await apiService.fetchProfile() {
                    threshold = Double(profile.hrThresholdBpm)
                }
                _ = try? await apiService.fetchGitHubStatus()
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await authService.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private func updateThreshold(_ value: Int) {
        // Debounce threshold updates
        isUpdatingThreshold = true

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            do {
                try await apiService.updateThreshold(value)
                watchConnectivity.sendThresholdUpdate(value)
            } catch {
                // Revert on error
                if let profile = apiService.profile {
                    threshold = Double(profile.hrThresholdBpm)
                }
            }
            isUpdatingThreshold = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthService.shared)
        .environmentObject(APIService.shared)
        .environmentObject(WatchConnectivityService.shared)
}
