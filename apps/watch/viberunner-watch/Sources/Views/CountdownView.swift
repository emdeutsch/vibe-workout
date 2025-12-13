import SwiftUI

struct CountdownView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Get Ready")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Countdown number
            Text("\(workoutManager.countdownSeconds)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: workoutManager.countdownSeconds)

            Text("Warming up sensors...")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Pulsing heart icon
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
        }
        .padding()
        .navigationTitle("Starting")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    CountdownView()
        .environmentObject(WorkoutManager.shared)
}
