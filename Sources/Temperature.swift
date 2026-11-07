import Foundation
import IOKit

// CPU thermal-zone keys are generation-specific. Keep platform mappings separate:
// the same key can be a CPU sensor on Apple Silicon and a powerboard on Intel.
// Mapping reference and MIT attribution: THIRD_PARTY_NOTICES.md.
struct CPUTemperatureProfile {
    let keys: [String]
    let averagesSensors: Bool
    static func forModel(_ model: String) -> CPUTemperatureProfile? {
        let generations: [(String, [String])] = [
            ("Apple M1", ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]),
            ("Apple M2", ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]),
            ("Apple M3", ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]),
            ("Apple M4", ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]),
            ("Apple M5", ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]),
        ]
        for (name, keys) in generations {
            // Match a complete generation number, never M1 against a future M10.
            if model == name || model.hasPrefix(name + " ") {
                return CPUTemperatureProfile(keys: keys, averagesSensors: true)
            }
        }
        if model.contains("Intel") {
            return CPUTemperatureProfile(keys: ["TC0D", "TC0E", "TC0F", "TCAC", "TCBC"], averagesSensors: false)
        }
        return nil
    }
}

// Read-only AppleSMC protocol; never issue an SMC write command.
final class CPUTemperatureReader {
    private let profile: CPUTemperatureProfile?
    var supportsDevice: Bool { profile != nil }
    private var connection: io_connect_t = 0
    private var keys: [(name: String, size: UInt32, type: UInt32)] = []
    private var nextRead: TimeInterval = 0
    private var cached: Double?

    init(model: String = cpuModelName()) {
        profile = CPUTemperatureProfile.forModel(model)
        guard let profile else { return }
        let device = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }
        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS else { connection = 0; return }
        for name in profile.keys {
            guard let info = request(name, command: 9), u32(info, 28) <= 32 else { continue }
            let size = u32(info, 28), type = u32(info, 32)
            if (type == 0x666c7420 && size == 4) || (type == 0x73703738 && size == 2) {
                keys.append((name, size, type))
            }
        }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    func invalidateCache() { nextRead = 0; cached = nil }

    func read(now: TimeInterval) -> Double? {
        guard now >= nextRead else { return cached }
        nextRead = now + 5
        let readings: [Double] = keys.compactMap { key in
            guard let bytes = request(key.name, command: 5, size: key.size) else { return nil }
            return Self.decode(Array(bytes[48..<48 + Int(key.size)]), type: key.type)
        }
        cached = readings.isEmpty ? nil : (profile?.averagesSensors == true ? readings.reduce(0, +) / Double(readings.count) : readings.first)
        return cached
    }
    static func decode(_ bytes: [UInt8], type: UInt32) -> Double? {
        let value: Double
        switch (type, bytes.count) {
        case (0x666c7420, 4):
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            value = Double(Float(bitPattern: bits))
        case (0x73703738, 2):
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default: return nil
        }
        return value.isFinite && value > 0 && value < 130 ? value : nil
    }
    private func request(_ name: String, command: UInt8, size: UInt32 = 0) -> [UInt8]? {
        guard connection != 0 else { return nil }
        var input = [UInt8](repeating: 0, count: 80)
        var output = input
        let code = name.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        for index in 0..<4 {
            input[index] = UInt8(truncatingIfNeeded: code >> (index * 8))
            input[28 + index] = UInt8(truncatingIfNeeded: size >> (index * 8))
        }
        input[42] = command
        var outputSize = 80
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, source.count, destination.baseAddress, &outputSize)
            }
        }
        guard status == KERN_SUCCESS, outputSize == 80, output[40] == 0 else { return nil }
        return output
    }
    private func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
}
