import Foundation
import SQLite3

struct CPUPoint: Codable, Equatable {
    let timestamp: Date
    let user: Double
    let system: Double
}

struct GPUPoint: Codable, Equatable {
    let timestamp: Date
    let total: Double
    let renderer: Double?
    let tiler: Double?

    var chartValues: [Double?] { [total, renderer, tiler] }
}

struct MemoryPoint: Codable, Equatable {
    let timestamp: Date
    let used: UInt64
    let total: UInt64
}

struct NetworkPoint: Codable, Equatable {
    let timestamp: Date
    let download: Double
    let upload: Double
}

struct HistorySample {
    let timestamp: Date
    let cpu: CPUPoint?
    let gpu: GPUPoint?
    let memory: MemoryPoint?
    let network: NetworkPoint?
    init(timestamp: Date, cpu: CPUPoint?, gpu: GPUPoint?, memory: MemoryPoint? = nil, network: NetworkPoint? = nil) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.network = network
    }
}

enum HistoryRange: Int, CaseIterable {
    case twoMinutes = 120, fifteenMinutes = 900, oneHour = 3600
    var duration: TimeInterval { TimeInterval(rawValue) }
    var localizationKey: String {
        switch self { case .twoMinutes: return "history.range.two_minutes"; case .fifteenMinutes: return "history.range.fifteen_minutes"; case .oneHour: return "history.range.one_hour" }
    }
    var title: String { L(localizationKey) }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.integer(forKey: "historyRange")) ?? .twoMinutes
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: "historyRange") }
}

struct HistoryWindow {
    static let duration: TimeInterval = 120
    let start: Date
    let end: Date
    let maximumDuration: TimeInterval

    init(earliest: Date? = nil, now: Date, duration: TimeInterval = Self.duration) {
        maximumDuration = duration.isFinite && duration >= 1 ? duration : Self.duration
        end = now
        let span: TimeInterval
        if let earliest, earliest <= now {
            span = min(maximumDuration, max(1, now.timeIntervalSince(earliest)))
        } else {
            span = maximumDuration
        }
        start = now.addingTimeInterval(-span)
    }

    // Select actual extrema from each bucket; never invent average samples.
    // Endpoints and both low/high values survive, with at most 240 points.
    static func reduced<T>(_ points: [T], timestamp: KeyPath<T, Date>, value: (T) -> Double, limit: Int = 240) -> [T] {
        reducedChannels(points, channels: 1, limit: limit) { [value($0)] }
    }
    static func reducedChannels<T>(_ points: [T], channels: Int, limit: Int = 240, values: (T) -> [Double]) -> [T] {
        guard points.count > limit else { return points }
        precondition(channels > 0 && limit >= 2 + 2 * channels)
        let samples = points.map(values)
        precondition(samples.allSatisfy { $0.count == channels })
        let buckets = max(1, (limit - 2) / (2 * channels))
        var indices: Set<Int> = [0, points.count - 1]
        for bucket in 0..<buckets {
            let start = 1 + bucket * (points.count - 2) / buckets
            let end = 1 + (bucket + 1) * (points.count - 2) / buckets
            guard start < end else { continue }
            for channel in 0..<channels {
                if let low = (start..<end).min(by: { samples[$0][channel] < samples[$1][channel] }) { indices.insert(low) }
                if let high = (start..<end).max(by: { samples[$0][channel] < samples[$1][channel] }) { indices.insert(high) }
            }
        }
        return indices.sorted().map { points[$0] }
    }

    func fraction(_ date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
    static func segments<T>(_ points: [T], timestamp: KeyPath<T, Date>, now: Date, duration: TimeInterval = Self.duration) -> [[T]] {
        let cutoff = now.addingTimeInterval(-duration)
        let visible = points.filter { $0[keyPath: timestamp] >= cutoff && $0[keyPath: timestamp] <= now }
            .sorted { $0[keyPath: timestamp] < $1[keyPath: timestamp] }
        // Connect the recorded endpoints across sampling pauses for a continuous
        // overview. Keep real timestamps; no interpolated samples are persisted.
        return visible.isEmpty ? [] : [visible]
    }

}

// All SQLite work and pending samples are owned by this serial queue.
// Incremental transactions avoid rewriting a full day of history on every save.
final class HistoryStore {
    static let retention: TimeInterval = 24 * 60 * 60
    private static let pendingLimit = Int(retention) + 1
    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Neylu", isDirectory: true).appendingPathComponent("history.sqlite")
    }
    private let queue = DispatchQueue(label: "local.Neylu.history", qos: .utility)
    private var database: OpaquePointer?
    private var pending: [HistorySample] = []
    private var lastWrite = ProcessInfo.processInfo.systemUptime
    var onError: ((String) -> Void)?
    var onRecovery: (() -> Void)?
    private var writeFailed = false

    struct StoreError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(url: URL = HistoryStore.defaultURL) throws {
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if url == Self.defaultURL {
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        let status = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? L("history.open_failed")
            if database != nil { sqlite3_close(database); database = nil }
            throw StoreError(message: message)
        }
        do {
            // Apply before enabling WAL so new sidecars inherit owner-only access.
            for path in [url.path, url.path + "-wal", url.path + "-shm"] where files.fileExists(atPath: path) {
                try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
            sqlite3_busy_timeout(database, 1_000)
            var statement: OpaquePointer?
            try prepare("PRAGMA user_version", into: &statement)
            let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
            sqlite3_finalize(statement)
            guard (0...2).contains(version) else { throw StoreError(message: String(format: L("history.unsupported_version_format"), String(version))) }
            try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE IF NOT EXISTS samples (timestamp REAL PRIMARY KEY, cpu_user REAL, cpu_system REAL, gpu_total REAL, gpu_renderer REAL, gpu_tiler REAL);")
                try execute("CREATE TABLE IF NOT EXISTS memory_samples (timestamp REAL PRIMARY KEY, used INTEGER NOT NULL, total INTEGER NOT NULL);")
                try execute("CREATE TABLE IF NOT EXISTS network_samples (timestamp REAL PRIMARY KEY, download REAL NOT NULL, upload REAL NOT NULL);")
                try execute("PRAGMA user_version=2; COMMIT;")
            } catch { try? execute("ROLLBACK"); throw error }
            try prune(now: Date())
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }
    deinit { if database != nil { sqlite3_close(database) } }

    func load(since: Date, now: Date = Date()) throws -> (cpu: [CPUPoint], gpu: [GPUPoint], memory: [MemoryPoint], network: [NetworkPoint]) {
        try queue.sync {
            var statement: OpaquePointer?
            try prepare("SELECT timestamp,cpu_user,cpu_system,gpu_total,gpu_renderer,gpu_tiler FROM samples WHERE timestamp>=? AND timestamp<=? ORDER BY timestamp", into: &statement)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
            var cpu: [CPUPoint] = [], gpu: [GPUPoint] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
                func value(_ column: Int32) -> Double? {
                    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
                    let value = sqlite3_column_double(statement, column)
                    return value.isFinite && (0...100).contains(value) ? value : nil
                }
                if let user = value(1), let system = value(2), user + system <= 100.001 {
                    cpu.append(CPUPoint(timestamp: date, user: user, system: system))
                }
                if let total = value(3) {
                    gpu.append(GPUPoint(timestamp: date, total: total, renderer: value(4), tiler: value(5)))
                }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw currentError() }
            return (cpu, gpu, try loadMemory(since: since, now: now), try loadNetwork(since: since, now: now))
        }
    }
    private func loadMemory(since: Date, now: Date) throws -> [MemoryPoint] {
        var statement: OpaquePointer?
        try prepare("SELECT timestamp,used,total FROM memory_samples WHERE timestamp>=? AND timestamp<=? ORDER BY timestamp", into: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        var result: [MemoryPoint] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let used = sqlite3_column_int64(statement, 1), total = sqlite3_column_int64(statement, 2)
            if used >= 0, total > 0, used <= total {
                result.append(MemoryPoint(timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), used: UInt64(used), total: UInt64(total)))
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw currentError() }
        return result
    }
    private func loadNetwork(since: Date, now: Date) throws -> [NetworkPoint] {
        var statement: OpaquePointer?
        try prepare("SELECT timestamp,download,upload FROM network_samples WHERE timestamp>=? AND timestamp<=? ORDER BY timestamp", into: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        var result: [NetworkPoint] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let download = sqlite3_column_double(statement, 1), upload = sqlite3_column_double(statement, 2)
            if download.isFinite, upload.isFinite, download >= 0, upload >= 0 {
                result.append(NetworkPoint(timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), download: download, upload: upload))
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw currentError() }
        return result
    }
    func append(_ sample: HistorySample) {
        queue.async { [self] in
            pending.append(sample)
            if ProcessInfo.processInfo.systemUptime - lastWrite >= 30 {
                do { try attemptWrite() } catch { onError?(error.localizedDescription) }
            }
        }
    }
    func flush() throws { try queue.sync { try attemptWrite() } }

    private func attemptWrite() throws {
        do {
            let saved = try writePending()
            if saved && writeFailed { writeFailed = false; onRecovery?() }
        } catch {
            writeFailed = true
            throw error
        }
    }

    private func writePending() throws -> Bool {
        // Failed storage must not cause an unbounded RAM backlog or retry on every
        // sampling tick. Bound to one day at the fastest supported interval.
        lastWrite = ProcessInfo.processInfo.systemUptime
        let cutoff = Date().addingTimeInterval(-Self.retention)
        pending.removeAll { $0.timestamp < cutoff }
        if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
        guard !pending.isEmpty else { return false }
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            try prepare("INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?,?)", into: &statement)
            var memoryStatement: OpaquePointer?, networkStatement: OpaquePointer?
            defer { sqlite3_finalize(statement); sqlite3_finalize(memoryStatement); sqlite3_finalize(networkStatement) }
            try prepare("INSERT OR REPLACE INTO memory_samples VALUES (?,?,?)", into: &memoryStatement)
            try prepare("INSERT OR REPLACE INTO network_samples VALUES (?,?,?)", into: &networkStatement)
            for sample in pending {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                let values: [Double?] = [sample.timestamp.timeIntervalSince1970, sample.cpu?.user, sample.cpu?.system, sample.gpu?.total, sample.gpu?.renderer, sample.gpu?.tiler]
                for (index, value) in values.enumerated() {
                    if let value, value.isFinite { sqlite3_bind_double(statement, Int32(index + 1), value) }
                    else { sqlite3_bind_null(statement, Int32(index + 1)) }
                }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
                if let memory = sample.memory {
                    sqlite3_reset(memoryStatement); sqlite3_clear_bindings(memoryStatement)
                    sqlite3_bind_double(memoryStatement, 1, sample.timestamp.timeIntervalSince1970)
                    sqlite3_bind_int64(memoryStatement, 2, Int64(memory.used))
                    sqlite3_bind_int64(memoryStatement, 3, Int64(memory.total))
                    guard sqlite3_step(memoryStatement) == SQLITE_DONE else { throw currentError() }
                }
                if let network = sample.network {
                    sqlite3_reset(networkStatement); sqlite3_clear_bindings(networkStatement)
                    sqlite3_bind_double(networkStatement, 1, sample.timestamp.timeIntervalSince1970)
                    sqlite3_bind_double(networkStatement, 2, network.download)
                    sqlite3_bind_double(networkStatement, 3, network.upload)
                    guard sqlite3_step(networkStatement) == SQLITE_DONE else { throw currentError() }
                }
            }
            try prune(now: Date())
            try execute("COMMIT")
            pending.removeAll(keepingCapacity: true)
            return true
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    private func prune(now: Date) throws {
        for table in ["samples", "memory_samples", "network_samples"] {
            var statement: OpaquePointer?
            try prepare("DELETE FROM \(table) WHERE timestamp<?", into: &statement)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, now.addingTimeInterval(-Self.retention).timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
        }
    }
    private func prepare(_ sql: String, into statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw currentError() }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw currentError() }
    }
    private func currentError() -> StoreError {
        StoreError(message: database.map { String(cString: sqlite3_errmsg($0)) } ?? L("history.not_open"))
    }
}
