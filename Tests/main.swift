import Foundation
import SQLite3

L10n.useResources(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NeyluHistoryTests-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let url = directory.appendingPathComponent("history.sqlite")
let now = Date()
func point(_ age: TimeInterval, user: Double = 20) -> CPUPoint {
    CPUPoint(timestamp: now.addingTimeInterval(-age), user: user, system: 5)
}
func sample(_ cpu: CPUPoint) -> HistorySample {
    HistorySample(timestamp: cpu.timestamp, cpu: cpu, gpu: GPUPoint(timestamp: cpu.timestamp, total: 45, renderer: 42, tiler: 44), memory: MemoryPoint(timestamp: cpu.timestamp, used: 32 * 1_024 * 1_024 * 1_024, total: 48 * 1_024 * 1_024 * 1_024), network: NetworkPoint(timestamp: cpu.timestamp, download: 98_765.4, upload: 1_234.5))
}
// SQLite stores Unix seconds as a Double. Date's reference-epoch conversion
// can round by one ULP; compare the exact values we actually persist.
func requireStoredCPU(_ actual: [CPUPoint], _ expected: [CPUPoint]) {
    precondition(actual.count == expected.count, "Stored CPU sample count differs")
    for (value, source) in zip(actual, expected) {
        precondition(value.user == source.user && value.system == source.system, "Stored CPU values differ")
        precondition(value.timestamp.timeIntervalSince1970 == source.timestamp.timeIntervalSince1970,
                     "Stored Unix timestamp differs")
    }
}

func sql(_ text: String, at url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else {
        fatalError(String(cString: sqlite3_errmsg(db)))
    }
}

var store: HistoryStore? = try HistoryStore(url: url)
func permissions(_ path: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as! NSNumber).intValue & 0o777
}
for path in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] where FileManager.default.fileExists(atPath: path.path) {
    let mode = try permissions(path)
    precondition(mode == 0o600)
}
// Upgrading an older installation must also harden already-existing files.
store = nil
try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
store = try HistoryStore(url: url)
let upgradedMode = try permissions(url)
precondition(upgradedMode == 0o600)
print("PASS: new and existing history databases and WAL sidecars are owner-only")
func restoredCount() -> Int { try! store!.load(since: now.addingTimeInterval(-120), now: now).cpu.count }
let first = point(12), second = point(10)
store!.append(sample(point(HistoryStore.retention + 60)))
store!.append(sample(first))
store!.append(sample(second))
try store!.flush()
store = nil
store = try HistoryStore(url: url)
let restored = try store!.load(since: now.addingTimeInterval(-HistoryStore.retention), now: now)
requireStoredCPU(restored.cpu, [first, second])
precondition(restored.gpu.count == 2)
precondition(restored.memory.count == 2 && restored.memory[0].used == 32 * 1_024 * 1_024 * 1_024)
precondition(restored.network.count == 2 && restored.network[0].download == 98_765.4)
print("PASS: durable round trip, timestamp/order preservation and retention pruning")

// A deliberately unrepresentable reference-epoch fraction must still preserve
// the exact Unix-epoch Double written to SQLite, not an approximate tolerance.
let fractional = Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down).nextUp)
precondition(fractional != Date(timeIntervalSince1970: fractional.timeIntervalSince1970))
var fractionalStore: HistoryStore? = try HistoryStore(url: directory.appendingPathComponent("fractional.sqlite"))
let fractionalPoint = CPUPoint(timestamp: fractional, user: 13, system: 7)
fractionalStore!.append(sample(fractionalPoint))
try fractionalStore!.flush()
requireStoredCPU(try fractionalStore!.load(since: now.addingTimeInterval(-120), now: now).cpu, [fractionalPoint])
fractionalStore = nil
print("PASS: sub-microsecond Date epoch conversion preserves exact persisted Unix timestamps")

// NULL hardware counters must round-trip independently of genuine zero values.
let partialURL = directory.appendingPathComponent("partial-gpu.sqlite")
let partialStore = try HistoryStore(url: partialURL)
let partialDate = now.addingTimeInterval(-4)
partialStore.append(HistorySample(timestamp: partialDate, cpu: nil,
    gpu: GPUPoint(timestamp: partialDate, total: 45, renderer: nil, tiler: 0)))
try partialStore.flush()
let partialGPU = try partialStore.load(since: now.addingTimeInterval(-120), now: now).gpu
precondition(partialGPU.count == 1 && partialGPU[0].total == 45)
precondition(partialGPU[0].renderer == nil && partialGPU[0].tiler == 0)
print("PASS: missing GPU counters remain NULL while real zero utilization is preserved")

// Verify atomic batch failure, recovery notification and retry with samples intact.
var recoveries = 0
store!.onRecovery = { recoveries += 1 }
try sql("CREATE TRIGGER fail_sample BEFORE INSERT ON samples WHEN NEW.cpu_user=90 BEGIN SELECT RAISE(ABORT,'injected test failure'); END", at: url)
let third = point(8), fourth = point(6, user: 90)
store!.append(sample(third))
store!.append(sample(fourth))
var rejected = false
do { try store!.flush() } catch { rejected = true }
precondition(rejected && recoveries == 0)
let afterRollback = try store!.load(since: now.addingTimeInterval(-120), now: now)
precondition(afterRollback.cpu.count == 2)
precondition(afterRollback.memory.count == 2 && afterRollback.network.count == 2)
try sql("DROP TRIGGER fail_sample", at: url)
try store!.flush()
precondition(restoredCount() == 4 && recoveries == 1)
store!.append(sample(fourth))
try store!.flush()
precondition(restoredCount() == 4 && recoveries == 1)
store = nil
print("PASS: transaction rollback, pending-batch retry and duplicate timestamp upsert")

let gapPoints = [point(140), point(40), point(38), point(12), point(10), point(-1)]
let segments = HistoryWindow.segments(gapPoints, timestamp: \.timestamp, now: now)
precondition(segments.count == 1)
precondition(segments[0] == [point(40), point(38), point(12), point(10)])
precondition(HistoryWindow.segments([CPUPoint](), timestamp: \.timestamp, now: now).isEmpty)
precondition(HistoryWindow(now: now).fraction(now.addingTimeInterval(-120)) == 0)
precondition(HistoryWindow(now: now).fraction(now) == 1)
print("PASS: real-time chart coordinates, expiry/future filtering and continuous restart/sleep endpoints without synthetic samples")

let origin = now.addingTimeInterval(-8)
let startup = HistoryWindow(earliest: origin, now: now)
precondition(startup.fraction(origin) == 0 && startup.fraction(now) == 1)
precondition(startup.fraction(now.addingTimeInterval(-4)) == 0.5)
let growing = HistoryWindow(earliest: origin, now: origin.addingTimeInterval(60))
precondition(abs(growing.fraction(now) - 8.0 / 60) < 0.000001)
let full = HistoryWindow(earliest: origin, now: origin.addingTimeInterval(120))
let rolling = HistoryWindow(earliest: origin, now: origin.addingTimeInterval(180))
precondition(full.end.timeIntervalSince(full.start) == 120)
precondition(rolling.end.timeIntervalSince(rolling.start) == 120)
precondition(rolling.fraction(origin) == 0 && rolling.fraction(rolling.end) == 1)
precondition(HistoryWindow(earliest: now, now: now).fraction(now) == 1)
precondition(HistoryWindow(earliest: now.addingTimeInterval(1), now: now).end.timeIntervalSince(HistoryWindow(earliest: now.addingTimeInterval(1), now: now).start) == 120)
print("PASS: startup samples span the chart, compress as data accumulates, and settle into a fixed two-minute window")

let corrupt = directory.appendingPathComponent("corrupt.sqlite")
let invalidData = Data("not a SQLite database".utf8)
try invalidData.write(to: corrupt)
rejected = false
do { _ = try HistoryStore(url: corrupt) } catch { rejected = true }
let preservedData = try Data(contentsOf: corrupt)
precondition(rejected && preservedData == invalidData)
try sql("PRAGMA user_version=999", at: url)
rejected = false
do { _ = try HistoryStore(url: url) } catch { rejected = true }
precondition(rejected)
print("PASS: corrupt and unsupported databases fail safely without replacing history")

let legacy = directory.appendingPathComponent("legacy.sqlite")
try sql("CREATE TABLE samples (timestamp REAL PRIMARY KEY, cpu_user REAL, cpu_system REAL, gpu_total REAL, gpu_renderer REAL, gpu_tiler REAL); INSERT INTO samples VALUES (\(now.addingTimeInterval(-30).timeIntervalSince1970),17,4,25,24,25); PRAGMA user_version=1", at: legacy)
var migrated: HistoryStore? = try HistoryStore(url: legacy)
let legacyData = try migrated!.load(since: now.addingTimeInterval(-120), now: now)
precondition(legacyData.cpu.count == 1 && legacyData.cpu[0].user == 17 && legacyData.gpu.count == 1)
precondition(legacyData.memory.isEmpty && legacyData.network.isEmpty)
migrated!.append(sample(point(2)))
try migrated!.flush()
migrated = nil
migrated = try HistoryStore(url: legacy)
let expanded = try migrated!.load(since: now.addingTimeInterval(-120), now: now)
precondition(expanded.cpu.count == 2 && expanded.gpu.count == 2)
precondition(expanded.memory.count == 1 && expanded.network.count == 1)
migrated = nil
print("PASS: v1-to-v2 migration preserves CPU/GPU history and restores real memory/network samples")
