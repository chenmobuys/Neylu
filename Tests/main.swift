import Foundation
import SQLite3

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
func sql(_ text: String, at url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else {
        fatalError(String(cString: sqlite3_errmsg(db)))
    }
}

var store: HistoryStore? = try HistoryStore(url: url)
func restoredCount() -> Int { try! store!.load(since: now.addingTimeInterval(-120), now: now).cpu.count }
let first = point(12), second = point(10)
store!.append(sample(point(HistoryStore.retention + 60)))
store!.append(sample(first))
store!.append(sample(second))
try store!.flush()
store = nil
store = try HistoryStore(url: url)
let restored = try store!.load(since: now.addingTimeInterval(-HistoryStore.retention), now: now)
precondition(restored.cpu == [first, second])
precondition(restored.gpu.count == 2)
precondition(restored.memory.count == 2 && restored.memory[0].used == 32 * 1_024 * 1_024 * 1_024)
precondition(restored.network.count == 2 && restored.network[0].download == 98_765.4)
print("PASS: durable round trip, timestamp/order preservation and retention pruning")

// Verify atomic batch failure and retry with the pending samples still intact.
try sql("CREATE TRIGGER fail_sample BEFORE INSERT ON samples WHEN NEW.cpu_user=90 BEGIN SELECT RAISE(ABORT,'injected test failure'); END", at: url)
let third = point(8), fourth = point(6, user: 90)
store!.append(sample(third))
store!.append(sample(fourth))
var rejected = false
do { try store!.flush() } catch { rejected = true }
precondition(rejected)
let afterRollback = try store!.load(since: now.addingTimeInterval(-120), now: now)
precondition(afterRollback.cpu.count == 2)
precondition(afterRollback.memory.count == 2 && afterRollback.network.count == 2)
try sql("DROP TRIGGER fail_sample", at: url)
try store!.flush()
precondition(restoredCount() == 4)
store!.append(sample(fourth))
try store!.flush()
precondition(restoredCount() == 4)
store = nil
print("PASS: transaction rollback, pending-batch retry and duplicate timestamp upsert")

let gapPoints = [point(140), point(40), point(38), point(12), point(10), point(-1)]
let segments = HistoryWindow.segments(gapPoints, timestamp: \.timestamp, now: now)
precondition(segments.count == 1)
precondition(segments[0] == [point(40), point(38), point(12), point(10)])
precondition(HistoryWindow.segments([CPUPoint](), timestamp: \.timestamp, now: now).isEmpty)
precondition(HistoryWindow.fraction(now.addingTimeInterval(-120), now: now) == 0)
precondition(HistoryWindow.fraction(now, now: now) == 1)
print("PASS: real-time chart coordinates, expiry/future filtering and continuous restart/sleep endpoints without synthetic samples")

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

// Rebranding must include committed WAL data and must never reset newer records.
let oldBrand = directory.appendingPathComponent("old-brand.sqlite")
let newBrand = directory.appendingPathComponent("new-brand/history.sqlite")
var oldBrandStore: HistoryStore? = try HistoryStore(url: oldBrand)
oldBrandStore!.append(sample(first))
try oldBrandStore!.flush()
precondition(FileManager.default.fileExists(atPath: oldBrand.path + "-wal"))
try HistoryStore.migrateLegacyHistoryIfNeeded(to: newBrand, from: oldBrand)
var newBrandStore: HistoryStore? = try HistoryStore(url: newBrand)
let copied = try newBrandStore!.load(since: now.addingTimeInterval(-120), now: now)
precondition(copied.cpu == [first] && copied.gpu.count == 1 && copied.memory.count == 1 && copied.network.count == 1)
precondition(FileManager.default.fileExists(atPath: oldBrand.path))
newBrandStore!.append(sample(second))
try newBrandStore!.flush()
newBrandStore = nil
try HistoryStore.migrateLegacyHistoryIfNeeded(to: newBrand, from: oldBrand)
newBrandStore = try HistoryStore(url: newBrand)
let kept = try newBrandStore!.load(since: now.addingTimeInterval(-120), now: now)
precondition(kept.cpu == [first, second])
newBrandStore = nil
oldBrandStore = nil
let absent = directory.appendingPathComponent("absent/history.sqlite")
try HistoryStore.migrateLegacyHistoryIfNeeded(to: absent, from: directory.appendingPathComponent("missing.sqlite"))
precondition(!FileManager.default.fileExists(atPath: absent.path))
let failedMigration = directory.appendingPathComponent("failed/history.sqlite")
rejected = false
do { try HistoryStore.migrateLegacyHistoryIfNeeded(to: failedMigration, from: corrupt) } catch { rejected = true }
precondition(rejected && !FileManager.default.fileExists(atPath: failedMigration.path))
let corruptAfterMigration = try Data(contentsOf: corrupt)
precondition(corruptAfterMigration == invalidData)
print("PASS: rebrand copies committed WAL and all metrics, preserves old data, never overwrites new history, handles missing/corrupt source")
