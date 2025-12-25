import SwiftUI

struct HeartRateCard: View {
    let isActive: Bool
    let bpm: Int
    let toolsUnlocked: Bool
    let threshold: Int

    private var heartRateColor: Color {
        if bpm == 0 { return .secondary }
        if isActive {
            return bpm >= threshold ? .hrAboveThreshold : .hrBelowThreshold
        }
        return .hrNeutral
    }

    private var statusColor: Color {
        toolsUnlocked ? .statusSuccess : .statusError
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            heartRateDisplay

            if isActive {
                activeWorkoutInfo
            } else {
                inactivePrompt
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }

    // MARK: - Heart Rate Display

    private var heartRateDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            if isActive && bpm > 0 {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(heartRateColor)
                    .symbolEffect(.pulse, options: .repeating)
            }

            Text("\(bpm)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(heartRateColor)
                .contentTransition(.numericText())

            Text("BPM")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Active Workout Info

    private var activeWorkoutInfo: some View {
        VStack(spacing: Spacing.sm) {
            // Tools status pill
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(toolsUnlocked ? "Tools Unlocked" : "Tools Locked")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.12))
            )

            // Threshold info
            Text("Threshold: \(threshold) BPM")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Inactive Prompt

    private var inactivePrompt: some View {
        Text("Start a workout to gate your repos")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

#Preview("Inactive") {
    HeartRateCard(isActive: false, bpm: 72, toolsUnlocked: false, threshold: 100)
        .padding()
}

#Preview("Active - Unlocked") {
    HeartRateCard(isActive: true, bpm: 115, toolsUnlocked: true, threshold: 100)
        .padding()
}

#Preview("Active - Locked") {
    HeartRateCard(isActive: true, bpm: 85, toolsUnlocked: false, threshold: 100)
        .padding()
}
