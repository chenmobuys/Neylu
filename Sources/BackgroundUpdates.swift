import Foundation

enum UpdateCheckSchedule {
    static let interval: TimeInterval = 24 * 60 * 60
    static func remaining(lastAttempt: Date?, now: Date) -> TimeInterval {
        guard let lastAttempt, lastAttempt <= now else { return 0 }
        return max(0, interval - now.timeIntervalSince(lastAttempt))
    }
}

@MainActor
final class BackgroundUpdateChecker {
    private let settings: MonitorSettings
    private let defaults: UserDefaults
    private let current: ReleaseVersion?
    private let check: (ReleaseVersion) async throws -> AvailableUpdate?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = 0
    static let attemptKey = "lastBackgroundUpdateAttempt"
    static let availableKey = "availableReleaseVersion"

    init(settings: MonitorSettings, defaults: UserDefaults = .standard,
         version: String = Bundle.main.object(forInfoDictionaryKey: "NeyluReleaseVersion") as? String ?? "",
         check: @escaping (ReleaseVersion) async throws -> AvailableUpdate? = { try await UpdateDiscovery.find(current: $0, architecture: UpdateController.architecture) }) {
        self.settings = settings
        self.defaults = defaults
        self.current = ReleaseVersion(version)
        self.check = check
        if let current, let cached = defaults.string(forKey: Self.availableKey).flatMap(ReleaseVersion.init), cached > current, current.channel < 3 || cached.channel == 3 {
            settings.availableUpdateVersion = cached.text
        } else {
            settings.availableUpdateVersion = nil
            defaults.removeObject(forKey: Self.availableKey)
        }
    }
    func start(now: Date = Date()) {
        timer?.invalidate()
        guard settings.automaticUpdateChecks, current != nil, task == nil else { return }
        let delay = max(30, UpdateCheckSchedule.remaining(lastAttempt: defaults.object(forKey: Self.attemptKey) as? Date, now: now))
        timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        timer?.tolerance = min(60, delay * 0.1)
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        generation += 1
        task?.cancel(); task = nil
    }
    func accept(_ update: AvailableUpdate?) {
        // A completed manual check is authoritative over an older background
        // request, including one whose transport ignores cancellation.
        stop()
        record(update)
        start()
    }
    private func record(_ update: AvailableUpdate?) {
        settings.availableUpdateVersion = update?.version.text
        if let update { defaults.set(update.version.text, forKey: Self.availableKey) }
        else { defaults.removeObject(forKey: Self.availableKey) }
    }
    func checkIfDue(now: Date = Date()) {
        guard settings.automaticUpdateChecks, task == nil, let current else { return }
        guard UpdateCheckSchedule.remaining(lastAttempt: defaults.object(forKey: Self.attemptKey) as? Date, now: now) == 0 else { start(now: now); return }
        defaults.set(now, forKey: Self.attemptKey) // Failures also back off across app restarts.
        let token = generation
        task = Task { [weak self, check] in
            guard !Task.isCancelled else { return }
            do {
                let result = try await check(current)
                guard let self, token == self.generation, !Task.isCancelled else { return }
                if self.settings.automaticUpdateChecks { self.record(result) }
            } catch { /* Silent daily backoff; manual checks still show actionable errors. */ }
            guard let self, token == self.generation else { return }
            self.task = nil
            self.start()
        }
    }
}
