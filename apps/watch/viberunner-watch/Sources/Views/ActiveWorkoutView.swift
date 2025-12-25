import SwiftUI

/// Main HR monitoring view - shows current heart rate and sync status
struct HRMonitorView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var phoneConnectivity: PhoneConnectivityService

    // Animation state for pulsing heart
    @State private var isPulsing = false
    // Track if we've shown the first reading (for animation)
    @State private var hasShownFirstReading = false

    /// Whether we're waiting for the first HR reading
    private var isWaitingForReading: Bool {
        workoutManager.isMonitoring && workoutManager.currentHeartRate == 0
    }

    /// Whether we have a valid HR reading to display
    private var hasValidReading: Bool {
        workoutManager.isMonitoring && workoutManager.currentHeartRate > 0
    }

    var body: some View {
        VStack(spacing: 12) {
            // Phone workout indicator (when phone has active workout)
            if workoutManager.isPhoneWorkoutActive {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.caption2)
                    Text("Workout Active")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.green.opacity(0.2))
                )
            }

            Spacer()

            // HR display
            VStack(spacing: 8) {
                if hasValidReading {
                    // Show actual heart rate with animation
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(workoutManager.currentHeartRate)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(heartRateColor)
                            .contentTransition(.numericText())

                        Text("BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.scale.combined(with: .opacity))

                    // Status indicator (only show when phone workout is active)
                    if workoutManager.isPhoneWorkoutActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isAboveThreshold ? .green : .red)
                                .frame(width: 8, height: 8)

                            Text(isAboveThreshold ? "Unlocked" : "Locked")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(isAboveThreshold ? .green : .red)
                        }
                    }
                } else if isWaitingForReading {
                    // Monitoring started but waiting for first reading - pulsing heart
                    pulsingHeartView
                        .transition(.opacity)

                    Text("Reading heart rate...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    // Not monitoring yet - show connecting state
                    pulsingHeartView
                        .transition(.opacity)

                    Text("Connecting to sensor...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: hasValidReading)
            .animation(.easeInOut(duration: 0.3), value: isWaitingForReading)

            Spacer()

            // Phone sync status - show actual data flow state, not just isReachable
            // isReachable becomes false when screen dims, but data still syncs via applicationContext
            phoneSyncStatusView
        }
        .padding()
        .onAppear {
            startPulsingAnimation()
        }
        .onChange(of: workoutManager.currentHeartRate) { _, newValue in
            if newValue > 0 && !hasShownFirstReading {
                hasShownFirstReading = true
            }
        }
    }

    /// Pulsing heart animation view
    private var pulsingHeartView: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 56))
            .foregroundStyle(.red)
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .opacity(isPulsing ? 1.0 : 0.7)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
    }

    private func startPulsingAnimation() {
        isPulsing = true
    }

    private var isAboveThreshold: Bool {
        let threshold = phoneConnectivity.currentThreshold ?? workoutManager.threshold
        return workoutManager.currentHeartRate >= threshold
    }

    private var heartRateColor: Color {
        if workoutManager.currentHeartRate == 0 {
            return .secondary
        }
        // Only show red/green based on threshold when phone workout is active
        if workoutManager.isPhoneWorkoutActive {
            return isAboveThreshold ? .green : .red
        }
        // Otherwise just show red (heart color) for passive monitoring
        return .red
    }

    /// Connected = mirroring active (best) OR reachable OR monitoring
    private var isConnectedToPhone: Bool {
        // Mirroring is the most reliable - works even when screen dims
        workoutManager.isMirroringActive || phoneConnectivity.isReachable || workoutManager.isMonitoring
    }

    /// Phone sync status view - show connected when data is flowing
    private var phoneSyncStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: isConnectedToPhone ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .font(.caption2)
            Text(isConnectedToPhone ? "Connected" : "Not Connected")
                .font(.caption2)
        }
        .foregroundStyle(isConnectedToPhone ? .green : .secondary)
    }
}

#Preview {
    HRMonitorView()
        .environmentObject(WorkoutManager.shared)
        .environmentObject(PhoneConnectivityService.shared)
}
