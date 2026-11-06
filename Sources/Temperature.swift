import Foundation
import IOKit

// Read-only AppleSMC protocol. M3 sensor groups are thermal zones, not individual cores.
// Probe only known CPU keys; never issue an SMC write command.
final class CPUTemperatureReader {
    private var connection: io_connect_t = 0
    private var keys: [(name: String, size: UInt32, type: UInt32)] = []
    private var nextRead: TimeInterval = 0
    private var cached: Double?

    init() {
        guard cpuModelName().contains("Apple M3") else { return }
        let device = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }
        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS else { connection = 0; return }
        let names = ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        for name in names {
            guard let info = request(name, command: 9), u32(info, 28) <= 32 else { continue }
            let size = u32(info, 28), type = u32(info, 32)
            if (type == 0x666c7420 && size == 4) || (type == 0x73703738 && size == 2) {
                keys.append((name, size, type))
            }
        }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    func read(now: TimeInterval) -> Double? {
        guard now >= nextRead else { return cached }
        nextRead = now + 5
        let readings: [Double] = keys.compactMap { key in
            guard let bytes = request(key.name, command: 5, size: key.size) else { return nil }
            let value = key.type == 0x666c7420
                ? Double(Float(bitPattern: u32(bytes, 48)))
                : Double(Int16(bitPattern: UInt16(bytes[48]) << 8 | UInt16(bytes[49]))) / 256
            return value.isFinite && value > 0 && value < 130 ? value : nil
        }
        cached = readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)
        return cached
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
