import Foundation
import IOKit

/// Read-only SMC temperature access. The protocol is undocumented; unavailable
/// keys and failed reads remain nil. Never writes keys or changes fan controls.
final class CPUTemperature {
    private var connection: io_connect_t = 0
    private let keys: [String]
    init() {
        keys = Self.sensorKeys(for: sysctlString("machdep.cpu.brand_string"))
        guard !keys.isEmpty else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    // CPU-only sensor identifiers cross-checked with Stats' per-generation map.
    // Probe all variants in that generation; absent keys never become zeroes.
    static func sensorKeys(for chip: String) -> [String] {
        let family = chip.split(separator: " ").prefix(2).joined(separator: " ")
        switch family {
        case "Apple M1": return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case "Apple M2": return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case "Apple M3": return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case "Apple M4": return ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case "Apple M5": return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        default: return []
        }
    }
    static func decode(type: UInt32, data: [UInt8]) -> Double? {
        let value: Double
        switch type {
        case 0x666c7420: // flt : little-endian Float Celsius.
            guard data.count == 4 else { return nil }
            value = Double(data.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case 0x73703738: // sp78: signed big-endian 8.8 fixed point.
            guard data.count == 2 else { return nil }
            value = Double(Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))) / 256
        default: return nil
        }
        guard value.isFinite, (10...120).contains(value) else { return nil }
        return value
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    func sample() -> Double? {
        let values = keys.compactMap(read)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    private func read(_ key: String) -> Double? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        // AppleSMC's 80-byte request: key at 0, metadata at 28,
        // result at 40, read command at 42, value bytes at 48.
        var input = [UInt8](repeating: 0, count: 80)
        var output = input
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        withUnsafeBytes(of: code) { input.replaceSubrange(0..<4, with: $0) }
        input[42] = 9 // Read key metadata.
        var size = 80
        guard IOConnectCallStructMethod(connection, 2, &input, 80, &output, &size) == KERN_SUCCESS,
              size == 80, output[40] == 0 else { return nil }
        let count = output[28..<32].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let type = output[32..<36].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard (type == 0x666c7420 && count == 4) || (type == 0x73703738 && count == 2) else { return nil }
        input.replaceSubrange(28..<32, with: output[28..<32])
        input[42] = 5 // Read bytes only.
        size = 80
        guard IOConnectCallStructMethod(connection, 2, &input, 80, &output, &size) == KERN_SUCCESS,
              size == 80, output[40] == 0 else { return nil }
        return Self.decode(type: type, data: Array(output[48..<48 + Int(count)]))
    }
}
