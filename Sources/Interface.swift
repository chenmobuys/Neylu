import AppKit
import SwiftUI
import CoreText

final class MonitorModel: ObservableObject {
    @Published var reading = Reading()
    @Published var history: [CPUPoint] = []
    @Published var gpuHistory: [GPUPoint] = []
    @Published var memoryHistory: [MemoryPoint] = []
    @Published var networkHistory: [NetworkPoint] = []
    @Published private(set) var chartWindow = HistoryWindow(now: Date())
    private var chartStart: Date?
    let settings = MonitorSettings()
    let layout = DetailLayout()
    let diskActions = DiskActions()
    let alerts = MonitorAlerts()
    var basis: UnitBasis { settings.basis }
    var loginEnabled: Bool {
        get { settings.loginEnabled }
        set { settings.loginEnabled = newValue }
    }
    var error: String? {
        get { alerts.message }
        set { alerts.message = newValue }
    }
    var onSettingsChange: (() -> Void)? {
        get { settings.onChange }
        set { settings.onChange = newValue }
    }
    private var historyStore: HistoryStore?
    private var historySaveMessage: String?
    init(persistHistory: Bool = true) {
        settings.onError = { [weak self] message in self?.alerts.message = message }
        if !persistHistory || CommandLine.arguments.contains("--screenshot-mode") { return }
        do {
            let store = try HistoryStore()
            let now = Date()
            let saved = try store.load(since: now.addingTimeInterval(-HistoryWindow.duration), now: now)
            history = saved.cpu
            gpuHistory = saved.gpu
            memoryHistory = saved.memory
            networkHistory = saved.network
            updateChartWindow(at: now)
            historyStore = store
            store.onError = { [weak self] message in
                DispatchQueue.main.async { self?.historySaveFailed(message) }
            }
            store.onRecovery = { [weak self] in DispatchQueue.main.async { self?.historySaveRecovered() } }
        } catch { self.error = L("history.unavailable_prefix") + error.localizedDescription }
    }
    func recordCPU(_ reading: Reading, at now: Date = Date()) {
        let cpu = reading.cpuReady ? CPUPoint(timestamp: now, user: reading.cpuUser, system: reading.cpuSystem) : nil
        let gpu = reading.gpuReady ? GPUPoint(timestamp: now, total: reading.gpu, renderer: reading.gpuRenderer, tiler: reading.gpuTiler) : nil
        let memory = reading.memoryReady ? MemoryPoint(timestamp: now, used: reading.usedMemory, total: reading.totalMemory) : nil
        let network = reading.networkReady ? NetworkPoint(timestamp: now, download: reading.download, upload: reading.upload) : nil
        let cutoff = now.addingTimeInterval(-HistoryWindow.duration)
        history.removeAll { $0.timestamp < cutoff }
        gpuHistory.removeAll { $0.timestamp < cutoff }
        memoryHistory.removeAll { $0.timestamp < cutoff }
        networkHistory.removeAll { $0.timestamp < cutoff }
        if history.isEmpty && gpuHistory.isEmpty && memoryHistory.isEmpty && networkHistory.isEmpty {
            chartStart = nil
        }
        if let cpu { history.append(cpu) }
        if let gpu { gpuHistory.append(gpu) }
        if let memory { memoryHistory.append(memory) }
        if let network { networkHistory.append(network) }
        updateChartWindow(at: now)
        if cpu != nil || gpu != nil || memory != nil || network != nil {
            historyStore?.append(HistorySample(timestamp: now, cpu: cpu, gpu: gpu, memory: memory, network: network))
        }
    }
    func updateChartWindow(at now: Date) {
        // Keep the recording origin after pruning so a full chart stays at 120s.
        // Every chart uses this same range and the latest sampling timestamp.
        if chartStart == nil {
            chartStart = [history.first?.timestamp, gpuHistory.first?.timestamp,
                          memoryHistory.first?.timestamp, networkHistory.first?.timestamp]
                .compactMap { $0 }.filter { $0 <= now }.min()
        }
        chartWindow = HistoryWindow(earliest: chartStart, now: now)
    }

    func saveHistoryNow() {
        do { try historyStore?.flush() }
        catch { historySaveFailed(error.localizedDescription) }
    }

    func historySaveFailed(_ message: String) {
        historySaveMessage = L("history.save_failed_prefix") + message
        error = historySaveMessage
    }
    func historySaveRecovered() {
        if let historySaveMessage, error == historySaveMessage { error = nil }
        historySaveMessage = nil
    }

}

// One layout model owns both allocation and drawing coordinates. Metrics keep
// their identities when a new slot is inserted at the left, middle or right.
struct MenuBarSlot: Equatable {
    let metric: MenuBarMetric
    let originX: CGFloat
    let width: CGFloat
}

struct MenuBarLayout {
    static let leadingTrim: CGFloat = 2.5
    let slots: [MenuBarSlot]
    let width: CGFloat
    init(basis: UnitBasis, configuration: MenuBarConfiguration) {
        let metrics = configuration.visibleMetrics
        var cursor: CGFloat = 0
        var result: [MenuBarSlot] = []
        for (index, metric) in metrics.enumerated() {
            let width: CGFloat = metric == .network ? 14 + MeterView.rateWidth(for: basis) : 29
            result.append(MenuBarSlot(metric: metric, originX: cursor, width: width))
            cursor += width
            if index < metrics.count - 1 { cursor += metric == .network ? 6 : 5 }
        }
        slots = result
        width = metrics.isEmpty ? 20 : ceil(cursor + 4 - Self.leadingTrim - (metrics.last == .network ? 3 : 5.5))
    }
}

// Always give the native button a canvas equal to its current bounds. The
// content stays at x=0; its unused tail is transparent, so the cell cannot
// center a short bitmap during either expansion or contraction.
struct StatusImageMask {
    let image: NSImage
    let contentWidth: CGFloat
    func render(in size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        for scale in [CGFloat(1), CGFloat(2)] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(size.width * scale)), pixelsHigh: Int(ceil(size.height * scale)),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            context.cgContext.scaleBy(x: scale, y: scale)
            context.imageInterpolation = .none
            let clip = NSRect(x: 0, y: 0, width: contentWidth, height: size.height)
                .intersection(NSRect(origin: .zero, size: size))
            if !clip.isEmpty {
                NSBezierPath(rect: clip).addClip()
                image.draw(in: NSRect(x: (contentWidth - image.size.width) / 2,
                    y: (size.height - image.size.height) / 2, width: image.size.width, height: image.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
            }
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            result.addRepresentation(bitmap)
        }
        result.isTemplate = image.isTemplate
        return result
    }
}

// A single fixed-width surface: macOS only sees one menu bar item.
final class MeterView: NSView {
    var basis: UnitBasis = .decimal { didSet { needsDisplay = true; updateAccessibility() } }
    static func rateWidth(for basis: UnitBasis) -> CGFloat {
        let digits = basis == .decimal ? "999" : "1023"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)]
        return ceil(basis.units.dropFirst().flatMap { unit in
            [digits, "10.0"].map { ("\($0) \(unit)/s" as NSString).size(withAttributes: attributes).width }
        }.max() ?? 0)
    }
    var configuration = MenuBarConfiguration.defaults { didSet { needsDisplay = true; updateAccessibility() } }
    static func meterWidth(for basis: UnitBasis, configuration: MenuBarConfiguration = .defaults) -> CGFloat {
        MenuBarLayout(basis: basis, configuration: configuration).width
    }
    private static let fallbackIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Neylu")!
    }()
    var reading = Reading() { didSet { needsDisplay = true; updateAccessibility() } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false) // The enclosing native status button owns accessibility.
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var accessibilitySummary: String {
        let summaries = configuration.visibleMetrics.map { metric -> String in
            if metric == .network {
                return L("metrics.upload") + " " + formattedRate(reading.upload, basis: basis, ready: reading.networkReady)
                    + ", " + L("metrics.download") + " " + formattedRate(reading.download, basis: basis, ready: reading.networkReady)
            }
            return metric.title + " " + Self.metricValue(metric, reading: reading)
        }
        return (["Neylu"] + summaries).joined(separator: " · ")
    }
    private func updateAccessibility() {
        (superview as? NSStatusBarButton)?.setAccessibilityLabel(accessibilitySummary)
    }
    func makeStatusImage() -> NSImage {
        if configuration.visibleMetrics.isEmpty {
            let icon = Self.fallbackIcon.copy() as! NSImage
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
        let layout = MenuBarLayout(basis: basis, configuration: configuration)
        let size = NSSize(width: layout.width, height: 22)
        let image = NSImage(size: size)
        // Materialize both display scales before handing the image to the menu bar.
        // A drawing-handler representation can be deferred to another display/context.
        for scale in [CGFloat(1), CGFloat(2)] {
            let pixelsWide = Int(ceil(size.width * scale))
            let pixelsHigh = Int(size.height * scale)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let cg = context.cgContext
            cg.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
            cg.translateBy(x: 0, y: CGFloat(pixelsHigh))
            cg.scaleBy(x: CGFloat(pixelsWide) / size.width, y: -scale)
            Self.drawContents(in: NSRect(origin: .zero, size: size), reading: reading,
                              basis: basis, configuration: configuration, color: .black)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        // AppKit tints this alpha mask for each screen's menu bar appearance,
        // including inactive displays and highlighted states.
        image.isTemplate = true
        return image
    }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = (superview as? NSStatusBarButton)?.isHighlighted == true ? .selectedMenuItemTextColor : .labelColor
        Self.drawContents(in: bounds, reading: reading, basis: basis, configuration: configuration, color: color)
    }
    private static func metricValue(_ metric: MenuBarMetric, reading: Reading) -> String {
        switch metric {
        case .memory: return percent(reading.memory, ready: reading.memoryReady)
        case .cpu: return percent(reading.cpu, ready: reading.cpuReady)
        case .gpu: return percent(reading.gpu, ready: reading.gpuReady)
        case .disk:
            let used = reading.diskTotal > 0 ? 100 * Double(reading.diskTotal - min(reading.diskTotal, reading.diskFree)) / Double(reading.diskTotal) : 0
            return percent(used, ready: reading.diskReady && reading.diskTotal > 0)
        case .network: return ""
        }
    }
    private static func drawContents(in bounds: NSRect, reading: Reading, basis: UnitBasis, configuration: MenuBarConfiguration,
                                     color: NSColor) {
        if configuration.visibleMetrics.isEmpty {
            let x = (bounds.width - 16) / 2
            Self.fallbackIcon.draw(in: NSRect(x: x, y: (bounds.height - 16) / 2, width: 16, height: 16),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        guard let drawing = NSGraphicsContext.current?.cgContext else { return }
        drawing.saveGState()
        drawing.translateBy(x: -MenuBarLayout.leadingTrim, y: 0)
        defer { drawing.restoreGState() }
        let top = (bounds.height - 22) / 2
        let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        let ctFont = rateFont as CTFont
        let rateAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ]
        // Text and icons share the ink centre, rather than font line-box offsets.
        func rateRow(_ bytes: Double, up: Bool, x: CGFloat, centerY: CGFloat) {
            let value = formattedRate(bytes, basis: basis, ready: reading.networkReady)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: rateAttributes))
            let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let halfHeight = rateFont.capHeight * 0.38
            let tipY = centerY + (up ? -halfHeight : halfHeight)
            let tailY = centerY + (up ? halfHeight : -halfHeight)
            let path = NSBezierPath()
            path.lineWidth = 0.75
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: x + 7, y: tailY))
            path.line(to: NSPoint(x: x + 7, y: tipY))
            path.move(to: NSPoint(x: x + 4.8, y: tipY + (up ? 2.2 : -2.2)))
            path.line(to: NSPoint(x: x + 7, y: tipY))
            path.line(to: NSPoint(x: x + 9.2, y: tipY + (up ? 2.2 : -2.2)))
            color.setStroke()
            path.stroke()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: x + 14, y: centerY + inkBounds.midY)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        let metricFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        func metricText(_ value: String, x: CGFloat, centerY: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): metricFont as CTFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: x + 14.5 - ink.midX, y: centerY + ink.midY)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        for slot in MenuBarLayout(basis: basis, configuration: configuration).slots {
            let metric = slot.metric
            let x = slot.originX
            if metric == .network {
                rateRow(reading.upload, up: true, x: x, centerY: top + 5.5)
                rateRow(reading.download, up: false, x: x, centerY: top + 16.5)
            } else {
                metricText(Self.metricValue(metric, reading: reading), x: x, centerY: top + 5.5)
                metricText(metric.shortLabel, x: x, centerY: top + 16.5)
            }
        }
    }
}

struct CPUChart: View {
    let points: [CPUPoint]
    let window: HistoryWindow
    var primaryColor = Color.blue.opacity(0.65)
    var accessibilityTitle = L("chart.cpu.label")
    var body: some View {
        Canvas { context, size in
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: window.end)
            for segment in segments {
                guard let first = segment.first, let last = segment.last else { continue }
                let start = size.width * window.fraction(first.timestamp)
                let end = size.width * window.fraction(last.timestamp)
                func area(total: Bool) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: start, y: size.height))
                    for point in segment {
                        let value = min(100, max(0, total ? point.user + point.system : point.system))
                        path.addLine(to: CGPoint(x: size.width * window.fraction(point.timestamp), y: size.height * (1 - value / 100)))
                    }
                    path.addLine(to: CGPoint(x: end, y: size.height))
                    path.closeSubpath()
                    return path
                }
                context.fill(area(total: true), with: .color(primaryColor))
                context.fill(area(total: false), with: .color(Color.red.opacity(0.65)))
            }
        }
        .clipped()
        .accessibilityLabel(accessibilityTitle)
        .help(L("chart.sampling_gap_hint"))
    }
}

struct GPUChart: View {
    let points: [GPUPoint]
    let window: HistoryWindow
    var language = AppLanguage.load()
    var body: some View {
        Canvas { context, size in
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: window.end)
            let colors: [Color] = [.blue, .red, .teal]
            // Only stack metrics actually present throughout the visible history.
            // Missing hardware counters never become a zero-height synthetic band.
            let visible = segments.flatMap { $0 }
            let series = (0..<3).filter { index in !visible.isEmpty && visible.allSatisfy { $0.chartValues[index] != nil } }
            for segment in segments {
                for (band, metric) in series.enumerated() {
                    let color = colors[metric]
                    func height(_ point: GPUPoint, through count: Int) -> CGFloat {
                        let sum = series.prefix(count).reduce(0.0) {
                            $0 + min(100, max(0, point.chartValues[$1]!))
                        }
                        return size.height * sum / (100 * Double(series.count))
                    }
                    var area = Path()
                    for (index, point) in segment.enumerated() {
                        let position = CGPoint(x: size.width * window.fraction(point.timestamp), y: size.height - height(point, through: band + 1))
                        if index == 0 { area.move(to: position) } else { area.addLine(to: position) }
                    }
                    for point in segment.reversed() {
                        area.addLine(to: CGPoint(x: size.width * window.fraction(point.timestamp), y: size.height - height(point, through: band)))
                    }
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.65)))
                }
            }
        }
        .clipped()
        .accessibilityLabel(L10n.text("chart.gpu.label", language: language))
        .help(L10n.text("chart.gpu.help", language: language))
    }
}

// Only topology/layout changes resize the panel; regular samples keep controls intact.
final class DetailLayout: ObservableObject {
    @Published var isVisible = true
    @Published var maximumMetricsHeight: CGFloat = 900 {
        didSet { if maximumMetricsHeight != oldValue { onSizeChange?() } }
    }
    @Published var metricsHeight: CGFloat = 480
    var onSizeChange: (() -> Void)?
    func measured(_ height: CGFloat) {
        guard height > 0, abs(height - metricsHeight) > 0.5 else { return }
        metricsHeight = height
        onSizeChange?()
    }
}
private struct OverviewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// Only metric content observes live readings. Native controls and any
// open settings menu retain their identity while the values and charts update.
struct DetailView: View {
    let model: MonitorModel
    @ObservedObject private var settings: MonitorSettings
    @ObservedObject private var layout: DetailLayout
    init(model: MonitorModel) {
        self.model = model
        self.settings = model.settings
        self.layout = model.layout
    }
    var body: some View {
        Group {
            if layout.isVisible { contents }
            else { Color.clear.frame(width: 380, height: layout.metricsHeight + 110) }
        }
    }
    private var contents: some View {
        VStack(spacing: 0) {
            Text(L("overview.title"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 14)
            ScrollView(.vertical) {
                MetricsOverviewView(model: model, settings: model.settings)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: OverviewHeightKey.self, value: geometry.size.height)
                    })
            }
            .frame(height: min(layout.metricsHeight, layout.maximumMetricsHeight))
            .onPreferenceChange(OverviewHeightKey.self) { layout.measured($0) }
            Divider().padding(.top, 16).padding(.bottom, 12)
            MonitorFooter(settings: model.settings)
            MonitorAlertView(alerts: model.alerts, onSizeChange: { layout.onSizeChange?() })
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)
        .frame(width: 380)
    }
}

struct MetricsOverviewView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var settings: MonitorSettings
    @ObservedObject private var diskActions: DiskActions
    init(model: MonitorModel, settings: MonitorSettings, inspection: Date? = nil) {
        self.model = model
        self.settings = settings
        self.diskActions = model.diskActions
        self._inspection = State(initialValue: inspection)
    }
    @State private var inspection: Date?
    private var inspectionDates: [Date] { model.history.map(\.timestamp) + model.gpuHistory.map(\.timestamp) + model.memoryHistory.map(\.timestamp) + model.networkHistory.map(\.timestamp) }
    private var r: Reading { model.reading }
    private let columnGap: CGFloat = 22
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: columnGap) {
                cpu.frame(maxWidth: .infinity)
                gpu.frame(maxWidth: .infinity)
            }
            Divider()
            HStack(alignment: .top, spacing: columnGap) {
                memory.frame(maxWidth: .infinity)
                network.frame(maxWidth: .infinity)
            }
            Divider()
            disk
            ForEach(r.externalDisks) { volume in
                Divider()
                externalDisk(volume)
            }
        }
        .alert(String(format: L("disk.eject_failed_format"), diskActions.failure?.name ?? ""),
               isPresented: Binding(get: { diskActions.failure != nil }, set: { if !$0 { diskActions.failure = nil } })) {
            Button(L("action.ok"), role: .cancel) { diskActions.failure = nil }
        } message: {
            Text(diskActions.failure?.message ?? "")
        }
    }
    private var cpu: some View {
        VStack(spacing: 7) {
            heading(MenuBarMetric.cpu.symbol, "CPU", value: percent(r.cpu, ready: r.cpuReady))
            fact(L("metrics.temperature"), value: r.cpuTemperature.map { String(format: "%.1f°C", $0) } ?? (r.cpuTemperatureSupported ? L("metrics.unavailable") : L("metrics.unsupported")))
                .help(r.cpuTemperature != nil ? L("temperature.sensor_hint") : (r.cpuTemperatureSupported ? L("temperature.no_sensor") : L("temperature.unsupported_device")))
            CPUChart(points: model.history, window: model.chartWindow)
                .chartInspection(date: $inspection, samples: inspectionDates, window: model.chartWindow, readout: ChartReadout.cpu(model.history, at: inspection, language: settings.language, window: model.chartWindow)).frame(height: 50).padding(.vertical, 3)
            VStack(spacing: 5) {
                breakdown(L("metrics.user"), color: .blue, value: r.cpuUser, ready: r.cpuReady)
                breakdown(L("metrics.system"), color: .red, value: r.cpuSystem, ready: r.cpuReady)
                breakdown(L("metrics.idle"), color: Color(nsColor: .tertiaryLabelColor), value: r.cpuIdle, ready: r.cpuReady)
            }
        }
    }
    private var gpu: some View {
        VStack(spacing: 7) {
            heading(MenuBarMetric.gpu.symbol, "GPU", value: percent(r.gpu, ready: r.gpuReady))
            fact(L("metrics.cores"), value: r.gpuCores.map { L10n.cores($0) } ?? "—")
            GPUChart(points: model.gpuHistory, window: model.chartWindow, language: settings.language)
                .chartInspection(date: $inspection, samples: inspectionDates, window: model.chartWindow, readout: ChartReadout.gpu(model.gpuHistory, at: inspection, language: settings.language, window: model.chartWindow)).frame(height: 50).padding(.vertical, 3)
                .overlay { if !r.gpuReady { Text(L("metrics.gpu_unavailable")).font(.system(size: 10)).foregroundStyle(.secondary) } }
            VStack(spacing: 5) {
                breakdown(L("metrics.gpu_utilization"), color: .blue, value: r.gpu, ready: r.gpuReady)
                breakdown(L("metrics.gpu_renderer"), color: .red, value: r.gpuRenderer ?? 0, ready: r.gpuReady && r.gpuRenderer != nil)
                breakdown("Tiler", color: .teal, value: r.gpuTiler ?? 0, ready: r.gpuReady && r.gpuTiler != nil)
            }
        }
    }
    private var memory: some View {
        VStack(spacing: 0) {
            heading(MenuBarMetric.memory.symbol, L("metrics.memory"), value: percent(r.memory, ready: r.memoryReady)).padding(.bottom, 8)
            VStack(spacing: 6) {
                fact(L("metrics.used"), value: r.memoryReady ? formattedMemory(r.usedMemory, basis: model.basis) : "—")
                fact(L("metrics.total"), value: r.memoryReady ? formattedMemory(r.totalMemory, basis: model.basis) : "—")
            }.frame(height: 42)
            MemoryChart(points: model.memoryHistory, window: model.chartWindow, language: settings.language)
                .chartInspection(date: $inspection, samples: inspectionDates, window: model.chartWindow, readout: ChartReadout.memory(model.memoryHistory, at: inspection, basis: model.basis, window: model.chartWindow)).frame(height: 36).padding(.top, 12).padding(.bottom, 10)
            fact(L("metrics.available"), value: r.memoryReady ? formattedMemory(r.totalMemory - min(r.totalMemory, r.usedMemory), basis: model.basis) : "—")
        }
    }
    private var network: some View {
        VStack(spacing: 0) {
            heading(MenuBarMetric.network.symbol, L("metrics.network")).padding(.bottom, 8)
            VStack(spacing: 6) {
                rateRow(L("metrics.download"), symbol: "arrow.down", bytes: r.download)
                rateRow(L("metrics.upload"), symbol: "arrow.up", bytes: r.upload)
            }.frame(height: 42)
            NetworkChart(points: model.networkHistory, window: model.chartWindow, language: settings.language)
                .chartInspection(date: $inspection, samples: inspectionDates, window: model.chartWindow, readout: ChartReadout.network(model.networkHistory, at: inspection, basis: model.basis, window: model.chartWindow)).frame(height: 36).padding(.top, 12).padding(.bottom, 10)
            fact("IP", value: r.address, truncatesValue: true).textSelection(.enabled).help(r.address)
        }
    }
    private var disk: some View {
        VStack(spacing: 9) {
            heading(MenuBarMetric.disk.symbol, r.diskName, value: r.diskReady && r.diskTotal > 0 ? percent(100 * Double(r.diskTotal - min(r.diskTotal, r.diskFree)) / Double(r.diskTotal), ready: true) : "—")
            ProgressView(value: r.diskTotal > 0 ? Double(r.diskTotal - min(r.diskTotal, r.diskFree)) / Double(r.diskTotal) : 0)
                .progressViewStyle(.linear).controlSize(.mini)
                .accessibilityLabel(L("disk.used_space"))
            HStack {
                Text(r.diskReady ? L("disk.available_prefix") + formattedMemory(r.diskFree, basis: model.basis) : L("disk.unavailable"))
                Spacer(minLength: 8)
                Text(r.diskReady ? L("disk.total_prefix") + formattedMemory(r.diskTotal, basis: model.basis) : "—").foregroundStyle(.secondary)
            }.font(.system(size: 10.5)).monospacedDigit()
            HStack(spacing: columnGap) {
                fact(L("metrics.disk_read"), value: formattedDiskRate(r.diskRead, basis: model.basis, ready: r.diskActivityReady)).frame(maxWidth: .infinity)
                fact(L("metrics.disk_write"), value: formattedDiskRate(r.diskWrite, basis: model.basis, ready: r.diskActivityReady)).frame(maxWidth: .infinity)
            }.padding(.top, 2).help(L("disk.startup_io_hint"))
        }
    }
    private func externalDisk(_ volume: ExternalDiskReading) -> some View {
        VStack(spacing: 9) {
            heading("externaldrive", volume.name, value: percent(100 * Double(volume.total - min(volume.total, volume.free)) / Double(volume.total), ready: volume.total > 0), ejectVolume: volume)
            ProgressView(value: volume.total > 0 ? Double(volume.total - min(volume.total, volume.free)) / Double(volume.total) : 0)
                .progressViewStyle(.linear).controlSize(.mini)
                .accessibilityLabel(L("disk.used_space"))
            HStack {
                Text(L("disk.available_prefix") + formattedMemory(volume.free, basis: model.basis))
                Spacer(minLength: 8)
                Text(L("disk.total_prefix") + formattedMemory(volume.total, basis: model.basis)).foregroundStyle(.secondary)
            }.font(.system(size: 10.5)).monospacedDigit()
            HStack(spacing: columnGap) {
                fact(L("metrics.disk_read"), value: formattedDiskRate(volume.read, basis: model.basis, ready: volume.activityReady)).frame(maxWidth: .infinity)
                fact(L("metrics.disk_write"), value: formattedDiskRate(volume.write, basis: model.basis, ready: volume.activityReady)).frame(maxWidth: .infinity)
            }.padding(.top, 2).help(L("disk.io_hint"))
        }
    }
    private func heading(_ symbol: String, _ title: String, value: String? = nil, ejectVolume: ExternalDiskReading? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(title).lineLimit(1).help(title)
            } icon: {
                Image(systemName: symbol).font(.system(size: 12, weight: .regular)).foregroundStyle(.secondary)
            }.font(.system(size: 11.5, weight: .medium))
            if let volume = ejectVolume {
                Button { diskActions.eject(volume) } label: {
                    if diskActions.ejectingID == volume.id {
                        ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "eject").font(.system(size: 11)).frame(width: 14, height: 14)
                    }
                }
                .buttonStyle(.borderless).controlSize(.small)
                .disabled(volume.volumeURL == nil || diskActions.ejectingID != nil)
                .help(L("disk.eject"))
                .accessibilityLabel(String(format: L("disk.eject_named_format"), volume.name))
            }
            Spacer(minLength: 3)
            if let value { Text(value).font(.system(size: 18, weight: .regular)).monospacedDigit().fixedSize() }
        }.frame(height: 24)
    }
    private func fact(_ label: String, value: String, truncatesValue: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle)
                .fixedSize(horizontal: !truncatesValue, vertical: false)
        }.font(.system(size: 10.5)).frame(height: 15).accessibilityElement(children: .combine)
    }
    private func breakdown(_ label: String, color: Color, value: Double, ready: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.75)).frame(width: 5, height: 5)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(percent(value, ready: ready)).monospacedDigit()
        }.font(.system(size: 11)).frame(height: 15).accessibilityElement(children: .combine)
    }
    private func rateRow(_ title: String, symbol: String, bytes: Double) -> some View {
        let parts = formattedRate(bytes, basis: model.basis, ready: r.networkReady).split(separator: " ", maxSplits: 1)
        return HStack(alignment: .center, spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary).frame(width: 9).accessibilityHidden(true)
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            Text(parts.first.map(String.init) ?? "—").font(.system(size: 13)).monospacedDigit().fixedSize()
            Text(parts.count > 1 ? String(parts[1]) : "").font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: model.basis == .binary ? 30 : 26, alignment: .leading)
        }.frame(height: 18).accessibilityElement(children: .combine)
    }
}
