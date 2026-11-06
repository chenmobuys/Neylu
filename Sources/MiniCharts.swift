import SwiftUI

struct MemoryChart: View {
    let points: [MemoryPoint]
    var body: some View {
        Canvas { context, size in
            let now = Date()
            for segment in HistoryWindow.segments(points, timestamp: \.timestamp, now: now) {
                guard let first = segment.first, let last = segment.last else { continue }
                var line = Path()
                for (index, point) in segment.enumerated() {
                    let fraction = point.total > 0 ? min(1, Double(point.used) / Double(point.total)) : 0
                    let position = CGPoint(x: size.width * HistoryWindow.fraction(point.timestamp, now: now), y: size.height * (1 - fraction))
                    if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
                }
                var area = line
                area.addLine(to: CGPoint(x: size.width * HistoryWindow.fraction(last.timestamp, now: now), y: size.height))
                area.addLine(to: CGPoint(x: size.width * HistoryWindow.fraction(first.timestamp, now: now), y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(.blue.opacity(0.24)))
                context.stroke(line, with: .color(.blue.opacity(0.85)), lineWidth: 0.8)
            }
        }
        .clipped()
        .accessibilityLabel("最近两分钟已用内存曲线，以物理内存总容量为满刻度")
        .help("已用内存历史，以物理容量为满刻度；这是使用量，不是内存压力。停采空档连接前后记录，不补写数据")
    }
}

struct NetworkChart: View {
    let points: [NetworkPoint]
    var body: some View {
        Canvas { context, size in
            let now = Date()
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: now)
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
                        let position = CGPoint(x: size.width * HistoryWindow.fraction(point.timestamp, now: now), y: middle + direction * max(0, point[keyPath: key]) / maximum * (middle - 1))
                        if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
                    }
                    var area = line
                    area.addLine(to: CGPoint(x: size.width * HistoryWindow.fraction(last.timestamp, now: now), y: middle))
                    area.addLine(to: CGPoint(x: size.width * HistoryWindow.fraction(first.timestamp, now: now), y: middle))
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.18)))
                    context.stroke(line, with: .color(color.opacity(0.9)), lineWidth: 0.8)
                }
            }
        }
        .clipped()
        .accessibilityLabel("最近两分钟网络数据速率曲线，蓝色下载在上，红色上传在下，上下行使用同一刻度")
        .help("上方蓝色：下载；下方红色：上传。共用刻度，随最近两分钟的峰值自动缩放。停采空档连接前后记录，不补写数据")
    }
}
