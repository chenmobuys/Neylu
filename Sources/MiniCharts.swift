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

struct NetworkChart: View {
    let points: [NetworkPoint]
    let window: HistoryWindow
    var language = AppLanguage.load()
    var body: some View {
        Canvas { context, size in
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: window.end, duration: window.maximumDuration)
            let maximum = max(1, segments.flatMap { $0 }.map { max($0.download, $0.upload) }.max() ?? 1) * 1.1
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
                        let position = CGPoint(x: size.width * window.fraction(point.timestamp), y: middle + direction * max(0, point[keyPath: key]) / maximum * (middle - 1))
                        if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
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
        .accessibilityLabel(L10n.text("chart.network.label", language: language))
        .help(L10n.text("chart.network.help", language: language))
    }
}
