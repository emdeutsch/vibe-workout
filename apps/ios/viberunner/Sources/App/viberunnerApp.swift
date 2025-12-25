import SwiftUI

@main
struct viberunnerApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var apiService = APIService.shared
    @StateObject private var workoutService = WorkoutService.shared
    @StateObject private var watchConnectivity = WatchConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(apiService)
                .environmentObject(workoutService)
                .environmentObject(watchConnectivity)
                .onAppear {
                    // Request HealthKit authorization for workout session mirroring
                    watchConnectivity.requestHealthKitAuthorization()
                    // Attempt to wake watch app for HR monitoring
                    watchConnectivity.requestWatchAppLaunch()
                }
        }
    }
}
