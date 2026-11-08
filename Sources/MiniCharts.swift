import SwiftUI

struct MemoryChart: View {
    let points: [MemoryPoint]
    let window: HistoryWindow
    var language = AppLanguage.load()
    var body: some View {
        Canvas { context, size in
            for segment in HistoryWindow.segments(points, timestamp: \.timestamp, now: window.end, duration: window.maximumDuration) {
                guard let first = segment.first, let last = segment.last else { continue }
                var line = Path()
                for (index, point) in segment.enumerated() {
                    let fraction = point.total > 0 ? min(1, Double(point.used) / Double(point.total)) : 0
                    let position = CGPoint(x: size.width * window.fraction(point.timestamp), y: size.height * (1 - fraction))
                    if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
                }
                var area = line
                area.addLine(to: CGPoint(x: size.width * window.fraction(last.timestamp), y: size.height))
                area.addLine(to: CGPoint(x: size.width * window.fraction(first.timestamp), y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(.blue.opacity(0.24)))
                context.stroke(line, with: .color(.blue.opacity(0.85)), lineWidth: 0.8)
            }
        }
        .clipped()
        .accessibilityLabel(L10n.text("chart.memory.label", language: language))
        .help(L10n.text("chart.memory.help", language: language))
    }
}

// A linear, explicitly bounded range keeps isolated historical spikes from
// flattening normal traffic. Clipped peaks are marked; samples stay unchanged.
struct NetworkChartScale: Equatable {
    let maximum: Double
    let hasClippedPeaks: Bool
    init(points: [NetworkPoint]) {
        let rates = points.flatMap { [$0.download, $0.upload] }.filter { $0.isFinite && $0 >= 0 }.sorted()
        let peak = rates.last ?? 0
        let typical = rates.isEmpty ? 0 : rates[min(rates.count - 1, Int(Double(rates.count - 1) * 0.9))]
        let ceiling = points.count >= 20 ? min(peak, max(1_024, typical * 3)) : peak
        maximum = max(1, ceiling) * 1.1
        hasClippedPeaks = peak > maximum
    }
    func fraction(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value / maximum)) : 0 }
}

struct NetworkChart: View {
    let points: [NetworkPoint]
    let window: HistoryWindow
    var language = AppLanguage.load()
    var basis: UnitBasis = .decimal
    var scale: NetworkChartScale? = nil
    var body: some View {
        let range = scale ?? NetworkChartScale(points: points)
        Canvas { context, size in
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: window.end, duration: window.maximumDuration)
            let middle = size.height / 2
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: middle))
            baseline.addLine(to: CGPoint(x: size.width, y: middle))
            context.stroke(baseline, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)
            let series: [(KeyPath<NetworkPoint, Double>, Double, Color)] = [(\.download, -1, .blue), (\.upload, 1, .red)]
            for segment in segments {
                guard let first = segment.first, let last = segment.last else { continue }
                for (key, direction, color) in series {
                    var line = Path()
                    for (index, point) in segment.enumerated() {
                        let position = CGPoint(x: size.width * window.fraction(point.timestamp), y: middle + direction * range.fraction(point[keyPath: key]) * (middle - 1))
                        if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
                        if point[keyPath: key] > range.maximum && (index == 0 || segment[index - 1][keyPath: key] <= range.maximum) {
                            let x = min(max(3, position.x), max(3, size.width - 3))
                            let edge: CGFloat = direction < 0 ? 0 : size.height
                            var marker = Path()
                            marker.move(to: CGPoint(x: x, y: edge))
                            marker.addLine(to: CGPoint(x: x - 3, y: edge - direction * 4))
                            marker.addLine(to: CGPoint(x: x + 3, y: edge - direction * 4))
                            marker.closeSubpath()
                            context.fill(marker, with: .color(color))
                        }
                    }
                    var area = line
                    area.addLine(to: CGPoint(x: size.width * window.fraction(last.timestamp), y: middle))
                    area.addLine(to: CGPoint(x: size.width * window.fraction(first.timestamp), y: middle))
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.18)))
                    context.stroke(line, with: .color(color.opacity(0.9)), lineWidth: 0.8)
                }
            }
        }
        .clipped()
        .overlay(alignment: .topTrailing) {
            if range.hasClippedPeaks {
                Text(String(format: L10n.text("chart.network.range_format", language: language), formattedRate(range.maximum, basis: basis)))
                    .font(.system(size: 8)).foregroundStyle(.secondary).allowsHitTesting(false)
            }
        }
        .accessibilityLabel(L10n.text("chart.network.label", language: language))
        .help(L10n.text("chart.network.help", language: language))
    }
}
