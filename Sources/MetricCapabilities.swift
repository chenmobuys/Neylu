import Foundation

// Support describes an exposed data source, not whether this sampling tick has
// a value. The sampler retains observed sources through transient failures.
struct MetricCapabilities: Equatable {
    var menuMetrics: Set<MenuBarMetric> = Set(MenuBarMetric.allCases)
    var gpuRenderer = true
    var gpuTiler = true
    var gpuCores = true
    var diskActivity = true
    static let basic = Self(menuMetrics: [.cpu, .memory, .network, .disk],
                            gpuRenderer: false, gpuTiler: false, gpuCores: false, diskActivity: false)
    func supports(_ metric: MenuBarMetric) -> Bool { menuMetrics.contains(metric) }
    func configuration(_ saved: MenuBarConfiguration) -> MenuBarConfiguration {
        MenuBarConfiguration(items: saved.items.map { MenuBarItem(metric: $0.metric, enabled: $0.enabled && supports($0.metric)) }, density: saved.density)
    }
    func moving(_ metric: MenuBarMetric, to visibleRow: Int, in saved: MenuBarConfiguration) -> MenuBarConfiguration {
        let visible = items(saved)
        guard visible.contains(where: { $0.metric == metric }), (0...visible.count).contains(visibleRow) else { return saved }
        let target: Int
        if visibleRow < visible.count {
            target = saved.items.firstIndex(where: { $0.metric == visible[visibleRow].metric })!
        } else if let last = visible.last {
            target = saved.items.firstIndex(where: { $0.metric == last.metric })! + 1
        } else { return saved }
        var result = saved
        result.move(metric, to: target)
        return result
    }
    func items(_ saved: MenuBarConfiguration) -> [MenuBarItem] { saved.items.filter { supports($0.metric) } }
}
