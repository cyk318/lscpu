import SwiftUI
import Charts
import LscpuCore

struct TrendChart: View {
    let samples: [Snapshot]
    let now: Date
    let color: Color
    let value: (Snapshot) -> Double?
    var secondary: ((Snapshot) -> Double?)? = nil
    var percentage = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Point: Identifiable {
        let id: Int
        let time: Date
        let value: Double
        let segment: Int
    }
    private func points(_ extract: (Snapshot) -> Double?) -> [Point] {
        var segment = 0
        var lastTime: Date?
        return samples.enumerated().compactMap { index, sample in
            guard let number = extract(sample), number.isFinite else { segment += 1; lastTime = nil; return nil }
            if let lastTime, sample.timestamp.timeIntervalSince(lastTime) > 5 { segment += 1 }
            lastTime = sample.timestamp
            return Point(id: index, time: sample.timestamp, value: number, segment: segment)
        }
    }
    var body: some View {
        let primary = points(value)
        let other = secondary.map(points) ?? []
        let maximum = percentage ? 100 : max(1_000, (primary + other).map(\.value).max() ?? 0) * 1.15
        Chart {
            ForEach(primary) { point in
                AreaMark(x: .value("Time", point.time), yStart: .value("Baseline", 0), yEnd: .value("Value", point.value), series: .value("Segment", "a\(point.segment)"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.19), color.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.time), y: .value("Value", point.value), series: .value("Segment", "a\(point.segment)"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            }
            ForEach(other) { point in
                LineMark(x: .value("Time", point.time), y: .value("Value", point.value), series: .value("Segment", "b\(point.segment)"))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [3, 3]))
                    .foregroundStyle(Metric.gpu.color.opacity(0.85))
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-60)...now)
        .chartYScale(domain: 0...maximum)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: now)
        .accessibilityHidden(true)
    }
}
