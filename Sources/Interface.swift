import AppKit
import SwiftUI
import ServiceManagement
import CoreText

final class MonitorModel: ObservableObject {
    @Published var reading = Reading()
    @Published var history: [CPUPoint] = []
    @Published var gpuHistory: [GPUPoint] = []
    @Published var memoryHistory: [MemoryPoint] = []
    @Published var networkHistory: [NetworkPoint] = []
    let settings = MonitorSettings()
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
    let cpuName = cpuModelName()
    private var historyStore: HistoryStore?
    init() {
        settings.onError = { [weak self] message in self?.alerts.message = message }
        do {
            let store = try HistoryStore()
            let now = Date()
            let saved = try store.load(since: now.addingTimeInterval(-HistoryWindow.duration), now: now)
            history = saved.cpu
            gpuHistory = saved.gpu
            memoryHistory = saved.memory
            networkHistory = saved.network
            historyStore = store
            store.onError = { [weak self] message in
                DispatchQueue.main.async { self?.error = "历史记录保存失败：" + message }
            }
        } catch { self.error = "历史记录不可用：" + error.localizedDescription }
    }
    func recordCPU(_ reading: Reading) {
        let now = Date()
        let cpu = reading.cpuReady ? CPUPoint(timestamp: now, user: reading.cpuUser, system: reading.cpuSystem) : nil
        let gpu = reading.gpuReady ? GPUPoint(timestamp: now, total: reading.gpu, renderer: reading.gpuRenderer, tiler: reading.gpuTiler) : nil
        let memory = reading.memoryReady ? MemoryPoint(timestamp: now, used: reading.usedMemory, total: reading.totalMemory) : nil
        let network = reading.networkReady ? NetworkPoint(timestamp: now, download: reading.download, upload: reading.upload) : nil
        let cutoff = now.addingTimeInterval(-HistoryWindow.duration)
        history.removeAll { $0.timestamp < cutoff }
        gpuHistory.removeAll { $0.timestamp < cutoff }
        memoryHistory.removeAll { $0.timestamp < cutoff }
        networkHistory.removeAll { $0.timestamp < cutoff }
        if let cpu { history.append(cpu) }
        if let gpu { gpuHistory.append(gpu) }
        if let memory { memoryHistory.append(memory) }
        if let network { networkHistory.append(network) }
        if cpu != nil || gpu != nil || memory != nil || network != nil {
            historyStore?.append(HistorySample(timestamp: now, cpu: cpu, gpu: gpu, memory: memory, network: network))
        }
    }
    func saveHistoryNow() {
        do { try historyStore?.flush() }
        catch { self.error = "历史记录保存失败：" + error.localizedDescription }
    }

}

// A single fixed-width surface: macOS only sees one menu bar item.
final class MeterView: NSView {
    var basis: UnitBasis = .decimal { didSet { needsDisplay = true; updateAccessibility() } }
    static func rateWidth(for basis: UnitBasis) -> CGFloat {
        let digits = basis == .decimal ? "999" : "1023"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)]
        return ceil(basis.units.dropFirst().map { ("\(digits) \($0)/s" as NSString).size(withAttributes: attributes).width }.max() ?? 0)
    }
    private static let leadingTrim: CGFloat = 2.5
    private static let trailingTrim: CGFloat = 5.5
    static func meterWidth(for basis: UnitBasis) -> CGFloat {
        14 + rateWidth(for: basis) + 6 + 29 + 5 + 29 + 4 - leadingTrim - trailingTrim
    }
    var reading = Reading() { didSet { needsDisplay = true; updateAccessibility() } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false) // The enclosing native status button owns accessibility.
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    var accessibilitySummary: String {
        "Neylu，上传 \(formattedRate(reading.upload, basis: basis, ready: reading.networkReady))，下载 \(formattedRate(reading.download, basis: basis, ready: reading.networkReady))，内存 \(percent(reading.memory, ready: reading.memoryReady))，CPU \(percent(reading.cpu, ready: reading.cpuReady))"
    }
    private func updateAccessibility() {
        (superview as? NSStatusBarButton)?.setAccessibilityLabel(accessibilitySummary)
    }
    func makeStatusImage() -> NSImage {
        let size = NSSize(width: Self.meterWidth(for: basis), height: 22)
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
            Self.drawContents(in: NSRect(origin: .zero, size: size), reading: reading, basis: basis, color: .white)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        // Preserve explicit white pixels; menu-bar template tint can override white.
        image.isTemplate = false
        return image
    }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = (superview as? NSStatusBarButton)?.isHighlighted == true ? .selectedMenuItemTextColor : .labelColor
        Self.drawContents(in: bounds, reading: reading, basis: basis, color: color)
    }
    private static func drawContents(in bounds: NSRect, reading: Reading, basis: UnitBasis, color: NSColor) {
        guard let drawing = NSGraphicsContext.current?.cgContext else { return }
        drawing.saveGState()
        drawing.translateBy(x: -Self.leadingTrim, y: 0)
        defer { drawing.restoreGState() }
        let top = (bounds.height - 22) / 2
        let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        let ctFont = rateFont as CTFont
        let rateAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ]
        // Text and icons share the ink centre, rather than font line-box offsets.
        func rateRow(_ bytes: Double, up: Bool, centerY: CGFloat) {
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
            path.move(to: NSPoint(x: 7, y: tailY))
            path.line(to: NSPoint(x: 7, y: tipY))
            path.move(to: NSPoint(x: 4.8, y: tipY + (up ? 2.2 : -2.2)))
            path.line(to: NSPoint(x: 7, y: tipY))
            path.line(to: NSPoint(x: 9.2, y: tipY + (up ? 2.2 : -2.2)))
            color.setStroke()
            path.stroke()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 14, y: centerY + inkBounds.midY)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        rateRow(reading.upload, up: true, centerY: top + 5.5)
        rateRow(reading.download, up: false, centerY: top + 16.5)
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
        let rateWidth = Self.rateWidth(for: basis)
        let memoryX = 14 + rateWidth + 6
        for (x, value, label) in [(memoryX, percent(reading.memory, ready: reading.memoryReady), "MEM"),
                                   (memoryX + 34, percent(reading.cpu, ready: reading.cpuReady), "CPU")] {
            metricText(value, x: x, centerY: top + 5.5)
            metricText(label, x: x, centerY: top + 16.5)
        }
    }
}

struct CPUChart: View {
    let points: [CPUPoint]
    var primaryColor = Color.blue.opacity(0.65)
    var accessibilityTitle = "最近两分钟 CPU 曲线，蓝色为用户，红色为系统"
    var body: some View {
        Canvas { context, size in
            let now = Date()
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: now)
            for segment in segments {
                guard let first = segment.first, let last = segment.last else { continue }
                let start = size.width * HistoryWindow.fraction(first.timestamp, now: now)
                let end = size.width * HistoryWindow.fraction(last.timestamp, now: now)
                func area(total: Bool) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: start, y: size.height))
                    for point in segment {
                        let value = min(100, max(0, total ? point.user + point.system : point.system))
                        path.addLine(to: CGPoint(x: size.width * HistoryWindow.fraction(point.timestamp, now: now), y: size.height * (1 - value / 100)))
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
        .help("退出或睡眠期间停止采样，空档仅连接前后记录，不补写数据")
    }
}

struct GPUChart: View {
    let points: [GPUPoint]
    var body: some View {
        Canvas { context, size in
            let now = Date()
            let segments = HistoryWindow.segments(points, timestamp: \.timestamp, now: now)
            let series: [(KeyPath<GPUPoint, Double>, Color)] = [
                (\.total, .blue),
                (\.renderer, .red),
                (\.tiler, .teal)
            ]
            // Equal-weight stacking: the three band heights sum to the mean,
            // while the legend continues to show each original percentage.
            for segment in segments {
                for (band, item) in series.enumerated() {
                    let color = item.1
                    func height(_ point: GPUPoint, through count: Int) -> CGFloat {
                        let sum = series.prefix(count).reduce(0.0) {
                            $0 + min(100, max(0, point[keyPath: $1.0]))
                        }
                        return size.height * sum / 300
                    }
                    var area = Path()
                    for (index, point) in segment.enumerated() {
                        let position = CGPoint(x: size.width * HistoryWindow.fraction(point.timestamp, now: now), y: size.height - height(point, through: band + 1))
                        if index == 0 { area.move(to: position) } else { area.addLine(to: position) }
                    }
                    for point in segment.reversed() {
                        area.addLine(to: CGPoint(x: size.width * HistoryWindow.fraction(point.timestamp, now: now), y: size.height - height(point, through: band)))
                    }
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.65)))
                }
            }
        }
        .clipped()
        .accessibilityLabel("最近两分钟 GPU 等权堆叠图，从下到上为蓝色利用率、红色渲染、青色 Tiler，总高度为三项平均值")
        .help("三项各按 1/3 缩放后堆叠；总高度为三项平均值，图例显示原始读数。停采空档连接前后记录，不补写数据")
    }
}

// Only metric content observes the two-second readings. Native controls and any
// open settings menu retain their identity while the values and charts update.
struct DetailView: View {
    let model: MonitorModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近 2 分钟").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                SettingsMenuButton(settings: model.settings).frame(width: 26, height: 24)
            }.padding(.bottom, 13)
            MetricsOverviewView(model: model, settings: model.settings)
            Divider().padding(.top, 16).padding(.bottom, 12)
            MonitorFooter()
            MonitorAlertView(alerts: model.alerts)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 14)
        .frame(width: 380)
    }
}

struct MetricsOverviewView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var settings: MonitorSettings
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
        }
    }
    private var cpu: some View {
        VStack(spacing: 7) {
            heading("cpu", "CPU", value: percent(r.cpu, ready: r.cpuReady))
            fact("温度", value: r.cpuTemperature.map { String(format: "%.1f°C", $0) } ?? "—°C")
                .help("CPU 有效温度传感器的平均值，每 5 秒采样")
            CPUChart(points: model.history).frame(height: 50).padding(.vertical, 3)
            VStack(spacing: 5) {
                breakdown("用户", color: .blue, value: r.cpuUser, ready: r.cpuReady)
                breakdown("系统", color: .red, value: r.cpuSystem, ready: r.cpuReady)
                breakdown("空闲", color: Color(nsColor: .tertiaryLabelColor), value: r.cpuIdle, ready: r.cpuReady)
            }
        }
    }
    private var gpu: some View {
        VStack(spacing: 7) {
            heading("cpu", "GPU", value: percent(r.gpu, ready: r.gpuReady))
            fact("核心", value: r.gpuCores.map { "\($0) 核" } ?? "—")
            GPUChart(points: model.gpuHistory).frame(height: 50).padding(.vertical, 3)
                .overlay { if !r.gpuReady { Text("GPU 数据不可用").font(.system(size: 10)).foregroundStyle(.secondary) } }
            VStack(spacing: 5) {
                breakdown("利用率", color: .blue, value: r.gpu, ready: r.gpuReady)
                breakdown("渲染", color: .red, value: r.gpuRenderer, ready: r.gpuReady)
                breakdown("Tiler", color: .teal, value: r.gpuTiler, ready: r.gpuReady)
            }
        }
    }
    private var memory: some View {
        VStack(spacing: 0) {
            heading("memorychip", "内存", value: percent(r.memory, ready: r.memoryReady)).padding(.bottom, 8)
            VStack(spacing: 6) {
                fact("已用", value: r.memoryReady ? formattedMemory(r.usedMemory, basis: model.basis) : "—")
                fact("总量", value: r.memoryReady ? formattedMemory(r.totalMemory, basis: model.basis) : "—")
            }.frame(height: 42)
            MemoryChart(points: model.memoryHistory).frame(height: 36).padding(.top, 12).padding(.bottom, 10)
            fact("可用", value: r.memoryReady ? formattedMemory(r.totalMemory - min(r.totalMemory, r.usedMemory), basis: model.basis) : "—")
        }
    }
    private var network: some View {
        VStack(spacing: 0) {
            heading("network", "网络").padding(.bottom, 8)
            VStack(spacing: 6) {
                rateRow("下载", symbol: "arrow.down", bytes: r.download)
                rateRow("上传", symbol: "arrow.up", bytes: r.upload)
            }.frame(height: 42)
            NetworkChart(points: model.networkHistory).frame(height: 36).padding(.top, 12).padding(.bottom, 10)
            fact("IP", value: r.address).textSelection(.enabled)
        }
    }
    private var disk: some View {
        VStack(spacing: 9) {
            heading("internaldrive", r.diskName, value: r.diskReady && r.diskTotal > 0 ? percent(100 * Double(r.diskTotal - min(r.diskTotal, r.diskFree)) / Double(r.diskTotal), ready: true) : "—")
            ProgressView(value: r.diskTotal > 0 ? Double(r.diskTotal - min(r.diskTotal, r.diskFree)) / Double(r.diskTotal) : 0)
                .progressViewStyle(.linear).controlSize(.mini)
                .accessibilityLabel("磁盘已用空间")
            HStack {
                Text(r.diskReady ? "可用 " + formattedMemory(r.diskFree, basis: model.basis) : "磁盘数据不可用")
                Spacer(minLength: 8)
                Text(r.diskReady ? "共 " + formattedMemory(r.diskTotal, basis: model.basis) : "—").foregroundStyle(.secondary)
            }.font(.system(size: 10.5)).monospacedDigit()
            HStack(spacing: columnGap) {
                fact("读取", value: formattedDiskRate(r.diskRead, basis: model.basis, ready: r.diskActivityReady)).frame(maxWidth: .infinity)
                fact("写入", value: formattedDiskRate(r.diskWrite, basis: model.basis, ready: r.diskActivityReady)).frame(maxWidth: .infinity)
            }.padding(.top, 2).help("启动盘所在物理磁盘的实时读写速度，包含同一 APFS 容器共享的卷")
        }
    }
    private func heading(_ symbol: String, _ title: String, value: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(title).lineLimit(1)
            } icon: {
                Image(systemName: symbol).font(.system(size: 12, weight: .regular)).foregroundStyle(.secondary)
            }.font(.system(size: 11.5, weight: .medium))
            Spacer(minLength: 3)
            if let value { Text(value).font(.system(size: 18, weight: .regular)).monospacedDigit().fixedSize() }
        }.frame(height: 24)
    }
    private func fact(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }.font(.system(size: 10.5)).frame(height: 15)
    }
    private func breakdown(_ label: String, color: Color, value: Double, ready: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color.opacity(0.75)).frame(width: 5, height: 5)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(percent(value, ready: ready)).monospacedDigit()
        }.font(.system(size: 11)).frame(height: 15)
    }
    private func rateRow(_ title: String, symbol: String, bytes: Double) -> some View {
        let parts = formattedRate(bytes, basis: model.basis, ready: r.networkReady).split(separator: " ", maxSplits: 1)
        return HStack(alignment: .center, spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary).frame(width: 9)
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 23, alignment: .leading)
            Spacer(minLength: 0)
            Text(parts.first.map(String.init) ?? "—").font(.system(size: 13)).monospacedDigit().fixedSize()
            Text(parts.count > 1 ? String(parts[1]) : "").font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: model.basis == .binary ? 30 : 26, alignment: .leading)
        }.frame(height: 18)
    }
}
