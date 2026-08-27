import Foundation

/// Host memory snapshot (Darwin). "Available" = free + inactive pages
/// (matching Activity Monitor's notion), converted to bytes.
public enum MemorySnapshot {
    public static func availableBytes() -> Int64 {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            // 0, not physical memory. This value is the numerator of an
            // admission decision (`VariantGate.admit`), so an over-optimistic
            // fallback ADMITS a launch that should be refused — the opposite of
            // the "safe to refuse on" the old comment claimed. Reporting no
            // available memory makes a failed reading refuse, which is the only
            // conservative direction here.
            return 0
        }
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let pageSize64 = UInt64(pageSize)
        let free = UInt64(stats.free_count) * pageSize64
        let inactive = UInt64(stats.inactive_count) * pageSize64
        return Int64(free + inactive)
    }
}
