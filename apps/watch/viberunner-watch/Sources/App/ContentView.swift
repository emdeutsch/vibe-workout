import SwiftUI

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        NavigationStack {
            if workoutManager.isPreparing {
                CountdownView()
            } else if workoutManager.isWorkoutActive {
                ActiveWorkoutView()
            } else {
                StartWorkoutView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager.shared)
        .environmentObject(PhoneConnectivityService.shared)
}
