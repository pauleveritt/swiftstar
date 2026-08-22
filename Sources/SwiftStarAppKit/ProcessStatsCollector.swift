import Foundation
import Darwin
import IOKit
import SwiftStarKit

public actor ProcessStatsCollector {
    private var previousCPUTicks: [UInt64]?
    private let power: IOReportPower?

    public init() {
        self.power = IOReportPower()
    }

    /// Returns a sanitized snapshot. `pid` nil → residentBytes nil (per-process);
    /// watts/GPU/CPU are system-wide and always collected. Actor-isolated so the
    /// IOReport sampling never runs on the main actor and the `previousCPUTicks`
    /// delta state is serialized across polls.
    public func collect(pid: pid_t?) async -> MachineSnapshot {
        let resident: Int64? = pid.flatMap { residentBytes(pid: $0) }
        let watts = (await power?.totalWatts()) ?? 0
        return DialLogic.sanitize(MachineSnapshot(
            residentBytes: resident,
            watts: watts,
            gpuUtilization: gpuUtilization(),
            cpuUtilization: cpuUtilization()
        ))
    }

    // MARK: memory — proc_pid_rusage, ri_phys_footprint (bytes)

    private func residentBytes(pid: pid_t) -> Int64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return Int64(info.ri_phys_footprint)
    }

    // MARK: CPU — host_processor_info tick delta

    private func cpuUtilization() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuInfoCount) == KERN_SUCCESS,
              let info = cpuInfo else { return 0 }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        var current = [UInt64](repeating: 0, count: Int(numCPUs) * stateCount)
        for core in 0..<Int(numCPUs) {
            let base = core * stateCount
            let ib = Int32(core) * CPU_STATE_MAX
            current[base + 0] = UInt64(info[Int(ib + CPU_STATE_USER)])
            current[base + 1] = UInt64(info[Int(ib + CPU_STATE_SYSTEM)])
            current[base + 2] = UInt64(info[Int(ib + CPU_STATE_IDLE)])
            current[base + 3] = UInt64(info[Int(ib + CPU_STATE_NICE)])
        }
        defer { previousCPUTicks = current }
        guard let prev = previousCPUTicks, prev.count == current.count else { return 0 }

        func delta(_ cur: UInt64, _ prev: UInt64) -> UInt64 { cur > prev ? cur - prev : 0 }
        var busy: UInt64 = 0, idle: UInt64 = 0
        for core in 0..<Int(numCPUs) {
            let base = core * stateCount
            busy += delta(current[base], prev[base]) + delta(current[base + 1], prev[base + 1]) + delta(current[base + 3], prev[base + 3])
            idle += delta(current[base + 2], prev[base + 2])
        }
        let total = busy + idle
        return total > 0 ? min(100.0, Double(busy) / Double(total) * 100.0) : 0
    }

    // MARK: GPU — IOAccelerator registry, PerformanceStatistics

    private func gpuUtilization() -> Double {
        guard let match = IOServiceMatching("IOAccelerator") else { return 0 }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var utilization = 0.0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any] {
                for key in ["GPU Activity(%)", "Device Utilization %", "gpuActivity"] {
                    if let v = (perf[key] as? NSNumber)?.doubleValue, v > 0 { utilization = v; break }
                }
            }
            IOObjectRelease(service)  // release exactly once per iteration
            if utilization > 0 { break }
            service = IOIteratorNext(iterator)
        }
        return min(100.0, utilization)
    }
}
