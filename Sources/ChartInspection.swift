import SwiftUI

struct ChartReadout {
    let timestamp: Date
    let value: String
    static func nearest<T>(_ points: [T], at date: Date?, timestamp: KeyPath<T, Date>, window: HistoryWindow? = nil) -> T? {
        guard let date else { return nil }
        let visible = points.filter { point in
            guard let window else { return true }
            return point[keyPath: timestamp] >= window.start && point[keyPath: timestamp] <= window.end
        }
        return visible.min { abs($0[keyPath: timestamp].timeIntervalSince(date)) < abs($1[keyPath: timestamp].timeIntervalSince(date)) }
    }
    static func cpu(_ points: [CPUPoint], at date: Date?, language: AppLanguage, window: HistoryWindow? = nil) -> Self? {
        guard let p = nearest(points, at: date, timestamp: \.timestamp, window: window) else { return nil }
        return Self(timestamp: p.timestamp, value: String(format: "%.0f%% · %@ %.0f%% · %@ %.0f%%", p.user + p.system, L10n.text("metrics.user", language: language), p.user, L10n.text("metrics.system", language: language), p.system))
    }
    static func gpu(_ points: [GPUPoint], at date: Date?, language: AppLanguage, window: HistoryWindow? = nil) -> Self? {
        guard let p = nearest(points, at: date, timestamp: \.timestamp, window: window) else { return nil }
        func value(_ n: Double?) -> String { n.map { String(format: "%.0f%%", $0) } ?? "—" }
        return Self(timestamp: p.timestamp, value: "\(value(p.total)) · \(L10n.text("metrics.gpu_renderer", language: language)) \(value(p.renderer)) · Tiler \(value(p.tiler))")
    }
    static func memory(_ points: [MemoryPoint], at date: Date?, basis: UnitBasis, window: HistoryWindow? = nil) -> Self? {
        guard let p = nearest(points, at: date, timestamp: \.timestamp, window: window) else { return nil }
        return Self(timestamp: p.timestamp, value: "\(formattedMemory(p.used, basis: basis)) / \(formattedMemory(p.total, basis: basis))")
    }
    static func network(_ points: [NetworkPoint], at date: Date?, basis: UnitBasis, window: HistoryWindow? = nil) -> Self? {
        guard let p = nearest(points, at: date, timestamp: \.timestamp, window: window) else { return nil }
        return Self(timestamp: p.timestamp, value: "↓ \(formattedRate(p.download, basis: basis)) · ↑ \(formattedRate(p.upload, basis: basis))")
    }
}

private struct ChartInspectionModifier: ViewModifier {
    @Binding var date: Date?
    let samples: [Date]
    let window: HistoryWindow
    let readout: ChartReadout?
    @Environment(\.colorSchemeContrast) private var contrast
    private var visible: [Date] { Array(Set(samples.filter { $0 >= window.start && $0 <= window.end })).sorted() }
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .overlay {
                    if let date {
                        Path { path in
                            let x = geometry.size.width * window.fraction(date)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }.stroke(.primary.opacity(contrast == .increased ? 0.9 : 0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let readout {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(readout.timestamp.formatted(date: .omitted, time: .standard))
                            Text(readout.value)
                        }
                        .font(.system(size: 9)).monospacedDigit()
                        .padding(3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .background(ChartHoverArea { point in
                    guard let point, geometry.size.width > 0 else { date = nil; return }
                    let fraction = min(1, max(0, point.x / geometry.size.width))
                    let target = window.start.addingTimeInterval(fraction * window.end.timeIntervalSince(window.start))
                    let selected = ChartReadout.nearest(visible, at: target, timestamp: \.self)
                    if date != selected { date = selected }
                })
        }
        .focusable()
        .onMoveCommand { direction in
            guard !visible.isEmpty, direction == .left || direction == .right else { return }
            let index = date.flatMap { visible.firstIndex(of: $0) } ?? (direction == .left ? visible.count : -1)
            date = visible[min(visible.count - 1, max(0, index + (direction == .left ? -1 : 1)))]
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("chart.inspect_hint"))
        .accessibilityValue(readout.map { $0.timestamp.formatted(date: .omitted, time: .standard) + " · " + $0.value } ?? "")
    }
}

extension View {
    func chartInspection(date: Binding<Date?>, samples: [Date], window: HistoryWindow, readout: ChartReadout?) -> some View {
        modifier(ChartInspectionModifier(date: date, samples: samples, window: window, readout: readout))
    }
}
