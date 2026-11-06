import Foundation
import AppKit
import IOKit
import Darwin

struct SystemSnapshot {
    var cpu: Double?; var gpu: Double?; var usedRAM: UInt64 = 0
    var totalRAM = ProcessInfo.processInfo.physicalMemory
    var diskTotal: UInt64 = 0; var diskFree: UInt64 = 0
    var wiredRAM: UInt64?
    var compressedRAM: UInt64?
    var swapUsed: UInt64?
    var memoryPressure = "Memory pressure unavailable"
    var uptime = ProcessInfo.processInfo.systemUptime
    var cpuTemperature: Double?
    var thermal = "Unavailable"
    var model = sysctlString("hw.model"); var chip = sysctlString("machdep.cpu.brand_string")
}
final class SystemSampler {
    private let temperature = CPUTemperature()
    private var previous: [UInt64]?
    func sample() -> SystemSnapshot {
        var s = SystemSnapshot()
        s.cpuTemperature = temperature.sample()
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if result == KERN_SUCCESS {
            let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3].map(UInt64.init)
            if let old = previous { let delta = zip(ticks, old).map { $0 &- $1 }; let total = delta.reduce(0,+); if total > 0 { s.cpu = 100 * Double(total - delta[2]) / Double(total) } }; previous = ticks
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) } }
        if vmResult == KERN_SUCCESS { s.usedRAM = (UInt64(vm.active_count) + UInt64(vm.inactive_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count) - min(UInt64(vm.purgeable_count) + UInt64(vm.external_page_count), UInt64(vm.active_count) + UInt64(vm.inactive_count))) * UInt64(vm_kernel_page_size) }
        if vmResult == KERN_SUCCESS {
            s.wiredRAM = UInt64(vm.wire_count) * UInt64(vm_kernel_page_size)
            s.compressedRAM = UInt64(vm.compressor_page_count) * UInt64(vm_kernel_page_size)
        }
        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { s.swapUsed = swap.xsu_used }
        var pressure: Int32 = 0; var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            s.memoryPressure = [1: "Normal", 2: "Warning", 4: "Critical"][pressure] ?? "Unknown"
        }
        if let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) { s.diskTotal = (values[.systemSize] as? NSNumber)?.uint64Value ?? 0; s.diskFree = (values[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0 }
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while true { let service = IOIteratorNext(iterator); if service == 0 { break }; defer { IOObjectRelease(service) }
                if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any], let value = stats["Device Utilization %"] as? NSNumber, (0...100).contains(value.doubleValue) { s.gpu = value.doubleValue }
            }
        }
        switch ProcessInfo.processInfo.thermalState { case .nominal: s.thermal = "Nominal"; case .fair: s.thermal = "Fair"; case .serious: s.thermal = "Serious"; case .critical: s.thermal = "Critical"; @unknown default: break }
        return s
    }
}
struct ProcessRow: Identifiable {
    let id: Int32; let uid: UInt32; let cpu: Double; let memory: UInt64; let command: String; let started: String
    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: id) }
    var name: String { app?.localizedName ?? URL(fileURLWithPath: command).lastPathComponent }
    // Classification is independent of whether a process can be terminated.
    var isSystem: Bool { uid == 0 || ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"].contains(where: { command.hasPrefix($0) }) }
    var protected: Bool { ProcessTerminationPolicy.isProtected(pid: id, uid: uid, executable: command) }

}
enum ProcessTerminationPolicy {
    // Protect session, desktop, security and IPC services by executable name;
    // Apple's application location alone does not make an app critical.
    static let criticalExecutables: Set<String> = [
        "kernel_task", "launchd", "loginwindow", "WindowServer", "Finder", "Dock",
        "SystemUIServer", "ControlCenter", "runningboardd", "cfprefsd", "tccd",
        "usernoted", "distnoted", "securityd", "coreauthd", "opendirectoryd",
        "trustd", "notifyd", "launchservicesd", "lsd", "watchdogd", "logd"
    ]
    static func isProtected(pid: Int32, uid: UInt32, executable: String) -> Bool {
        if pid <= 1 || pid == getpid() || uid != getuid() { return true }
        let path = URL(fileURLWithPath: executable).standardizedFileURL.path
        return criticalExecutables.contains(URL(fileURLWithPath: path).lastPathComponent)
    }
}
enum ProcessManager {
    static func sample() throws -> [ProcessRow] {
        let output = try Shell.checked("/bin/ps", ["-axo", "pid=,uid=,%cpu=,rss=,lstart=,comm="])
        return output.split(separator: "\n").compactMap { line in
            let p = line.split(maxSplits: 9, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard p.count == 10, let pid = Int32(p[0]), let uid = UInt32(p[1]), let cpu = Double(p[2]), let rss = UInt64(p[3]) else { return nil }
            return ProcessRow(id: pid, uid: uid, cpu: cpu, memory: rss * 1024, command: String(p[9]).trimmingCharacters(in: .whitespaces), started: p[4...8].joined(separator: " "))
        }.sorted { $0.cpu > $1.cpu }
    }
    static func terminate(_ row: ProcessRow, force: Bool) throws {
        guard let current = try sample().first(where: { $0.id == row.id }), current.started == row.started, current.command == row.command else { throw AppError.message("Process exited or its identity changed. Refresh the list.") }
        guard !current.protected else { throw AppError.message("Protected system process, another user's process, or macino itself.") }
        if let app = current.app { let ok = force ? app.forceTerminate() : app.terminate(); if !ok { throw AppError.message("The application declined the request.") } }
        else if kill(current.id, force ? SIGKILL : SIGTERM) != 0 { throw AppError.message(String(cString: strerror(errno))) }
    }
}
