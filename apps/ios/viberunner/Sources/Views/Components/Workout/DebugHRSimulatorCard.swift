#if DEBUG
import SwiftUI

struct DebugHRSimulatorCard: View {
    @EnvironmentObject var workoutService: WorkoutService

    private let threshold = Config.defaultHRThreshold

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Header with toggle
            HStack(spacing: Spacing.md) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(workoutService.isSimulatingHR ? .pink : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("HR Simulator")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(workoutService.isSimulatingHR
                         ? "\(workoutService.manualBPM) BPM"
                         : "Tap to simulate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { workoutService.isSimulatingHR },
                    set: { _ in workoutService.toggleHRSimulator() }
                ))
                .labelsHidden()
                .tint(.pink)
            }

            // Controls (only show when simulator is on)
            if workoutService.isSimulatingHR {
                VStack(spacing: Spacing.sm) {
                    // Slider
                    HStack {
                        Text("50")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(
                                get: { Double(workoutService.manualBPM) },
                                set: { workoutService.setManualHeartRate(Int($0)) }
                            ),
                            in: 50...180,
                            step: 1
                        )
                        .tint(workoutService.manualBPM >= threshold ? Color.hrAboveThreshold : Color.hrBelowThreshold)

                        Text("180")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Current value display
                    Text("\(workoutService.manualBPM) BPM")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(workoutService.manualBPM >= threshold ? Color.hrAboveThreshold : Color.hrBelowThreshold)

                    // Preset buttons
                    HStack(spacing: Spacing.sm) {
                        PresetButton(
                            title: "Below",
                            color: .hrBelowThreshold
                        ) {
                            workoutService.setManualHeartRate(threshold - 10)
                        }

                        PresetButton(
                            title: "Threshold",
                            color: .statusWarning
                        ) {
                            workoutService.setManualHeartRate(threshold)
                        }

                        PresetButton(
                            title: "Above",
                            color: .hrAboveThreshold
                        ) {
                            workoutService.setManualHeartRate(threshold + 10)
                        }
                    }

                    // Threshold indicator
                    Text("Threshold: \(threshold) BPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(.pink.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(.pink.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(color.opacity(0.2))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    DebugHRSimulatorCard()
        .environmentObject(WorkoutService.shared)
        .padding()
}
#endif
