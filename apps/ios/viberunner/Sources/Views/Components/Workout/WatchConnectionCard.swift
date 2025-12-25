import SwiftUI

struct WatchConnectionCard: View {
    @EnvironmentObject var watchConnectivity: WatchConnectivityService

    /// Consider data "fresh" if received within last 30 seconds
    private let dataFreshnessThreshold: TimeInterval = 30

    /// Connected = mirroring active OR reachable OR receiving data recently
    private var isConnected: Bool {
        // Mirroring is the most reliable - works even when watch screen dims
        if watchConnectivity.isMirroringActive {
            return true
        }
        if watchConnectivity.isReachable {
            return true
        }
        // Also consider connected if we've received HR data recently
        guard let lastTimestamp = watchConnectivity.lastReceivedTimestamp else {
            return false
        }
        return Date().timeIntervalSince(lastTimestamp) < dataFreshnessThreshold
    }

    private var statusColor: Color {
        isConnected ? Color.statusSuccess : Color.secondary
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Watch icon with connection indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(statusColor)

                Circle()
                    .fill(isConnected ? Color.statusSuccess : Color.secondary)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(watchConnectivity.isWatchAppInstalled ? "Apple Watch" : "Watch Not Found")
                    .font(.subheadline.weight(.medium))

                Text(isConnected ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Last received BPM
            if let lastBPM = watchConnectivity.lastReceivedBPM {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                    Text("\(lastBPM)")
                        .font(.headline)
                }
                .foregroundStyle(Color.hrNeutral)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    WatchConnectionCard()
        .environmentObject(WatchConnectivityService.shared)
        .padding()
}
