import SwiftUI
import Charts

// MARK: - Chart Data Point

struct HRChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let bpm: Int
    let minBpm: Int?
    let maxBpm: Int?
}

// MARK: - Heart Rate Chart View

struct HeartRateChartView: View {
    let dataPoints: [HRChartPoint]
    let thresholdBpm: Int
    let showThreshold: Bool
    let showRange: Bool

    init(
        dataPoints: [HRChartPoint],
        thresholdBpm: Int = 100,
        showThreshold: Bool = true,
        showRange: Bool = true
    ) {
        self.dataPoints = dataPoints
        self.thresholdBpm = thresholdBpm
        self.showThreshold = showThreshold
        self.showRange = showRange
    }

    var body: some View {
        Chart {
            // Range area (min to max) if available
            if showRange {
                ForEach(dataPoints.filter { $0.minBpm != nil && $0.maxBpm != nil }) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Min", point.minBpm!),
                        yEnd: .value("Max", point.maxBpm!)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.red.opacity(0.2), .red.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }

            // Main HR line
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("BPM", point.bpm)
                )
                .foregroundStyle(
                    point.bpm >= thresholdBpm ? Color.green : Color.red
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Threshold line
            if showThreshold {
                RuleMark(y: .value("Threshold", thresholdBpm))
                    .foregroundStyle(.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(thresholdBpm)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
            }
        }
        .chartYScale(domain: yAxisDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let bpm = value.as(Int.self) {
                        Text("\(bpm)")
                            .font(.caption2)
                    }
                }
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(format: .dateTime.hour().minute())
                AxisGridLine()
            }
        }
    }

    private var yAxisDomain: ClosedRange<Int> {
        guard !dataPoints.isEmpty else {
            return 50...200
        }

        let allValues = dataPoints.flatMap { point -> [Int] in
            var values = [point.bpm]
            if let min = point.minBpm { values.append(min) }
            if let max = point.maxBpm { values.append(max) }
            return values
        }

        let minVal = max(40, (allValues.min() ?? 60) - 10)
        let maxVal = min(220, (allValues.max() ?? 180) + 10)

        return minVal...maxVal
    }
}

// MARK: - Compact Chart View (for list items)

struct HeartRateSparklineView: View {
    let dataPoints: [HRChartPoint]
    let thresholdBpm: Int

    var body: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("BPM", point.bpm)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.red, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yAxisDomain)
    }

    private var yAxisDomain: ClosedRange<Int> {
        guard !dataPoints.isEmpty else {
            return 50...200
        }

        let bpms = dataPoints.map { $0.bpm }
        let minVal = max(40, (bpms.min() ?? 60) - 5)
        let maxVal = min(220, (bpms.max() ?? 180) + 5)

        return minVal...maxVal
    }
}

// MARK: - Live Heart Rate Chart (for active workout)

struct LiveHeartRateChartView: View {
    let currentBPM: Int
    let threshold: Int
    let recentSamples: [HRChartPoint]

    var body: some View {
        VStack(spacing: 8) {
            // Current HR display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)

                Text("\(currentBPM)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(currentBPM >= threshold ? .green : .red)

                Text("BPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Mini chart
            if !recentSamples.isEmpty {
                HeartRateChartView(
                    dataPoints: recentSamples,
                    thresholdBpm: threshold,
                    showThreshold: true,
                    showRange: false
                )
                .frame(height: 120)
            }
        }
    }
}

// MARK: - Helper Extensions

extension Array where Element == HRSample {
    func toChartPoints() -> [HRChartPoint] {
        compactMap { sample in
            guard let date = sample.timestamp else { return nil }
            return HRChartPoint(date: date, bpm: sample.bpm, minBpm: nil, maxBpm: nil)
        }
    }
}

extension Array where Element == HRBucket {
    func toChartPoints() -> [HRChartPoint] {
        compactMap { bucket in
            guard let date = bucket.startDate else { return nil }
            return HRChartPoint(
                date: date,
                bpm: bucket.avgBpm,
                minBpm: bucket.minBpm,
                maxBpm: bucket.maxBpm
            )
        }
    }
}

extension Array where Element == Int {
    /// Convert raw BPM values to chart points with synthetic timestamps
    func toChartPoints() -> [HRChartPoint] {
        let now = Date()
        return enumerated().map { index, bpm in
            HRChartPoint(
                date: now.addingTimeInterval(Double(index - count) * 60),
                bpm: bpm,
                minBpm: nil,
                maxBpm: nil
            )
        }
    }
}

// MARK: - Previews

#Preview("Full Chart") {
    let now = Date()
    let points = (0..<60).map { i in
        HRChartPoint(
            date: now.addingTimeInterval(Double(i) * -60),
            bpm: Int.random(in: 80...150),
            minBpm: Int.random(in: 70...90),
            maxBpm: Int.random(in: 140...170)
        )
    }.reversed()

    return HeartRateChartView(
        dataPoints: Array(points),
        thresholdBpm: 100
    )
    .frame(height: 200)
    .padding()
}

#Preview("Sparkline") {
    let now = Date()
    let points = (0..<30).map { i in
        HRChartPoint(
            date: now.addingTimeInterval(Double(i) * -60),
            bpm: Int.random(in: 90...130),
            minBpm: nil,
            maxBpm: nil
        )
    }.reversed()

    return HeartRateSparklineView(
        dataPoints: Array(points),
        thresholdBpm: 100
    )
    .frame(width: 100, height: 40)
    .padding()
}
