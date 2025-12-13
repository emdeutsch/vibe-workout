import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "heart.fill")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            GateReposView()
                .tabItem {
                    Label("Repos", systemImage: "folder.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService.shared)
        .environmentObject(APIService.shared)
        .environmentObject(WorkoutService.shared)
        .environmentObject(WatchConnectivityService.shared)
}
