import Darwin
import Foundation
import IOKit
import IOKit.ps

enum Probes {
    // MARK: sysctl

    static func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    // MARK: CPU — cumulative tick counters since boot

    static func cpuTicks() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }

    static func busyPercent(from prev: host_cpu_load_info, to now: host_cpu_load_info) -> Double {
        let p = [prev.cpu_ticks.0, prev.cpu_ticks.1, prev.cpu_ticks.2, prev.cpu_ticks.3]
        let n = [now.cpu_ticks.0, now.cpu_ticks.1, now.cpu_ticks.2, now.cpu_ticks.3]
        let deltas = zip(n, p).map { $0 &- $1 }
        let busy = deltas[Int(CPU_STATE_USER)] &+ deltas[Int(CPU_STATE_SYSTEM)] &+ deltas[Int(CPU_STATE_NICE)]
        let total = deltas.reduce(0, &+)
        guard total > 0 else { return 0 }
        return min(Double(busy) / Double(total) * 100, 100)
    }

    // MARK: Memory — HOST_VM_INFO64 page counts are in kernel page units (16 KiB on arm64)

    static func vmStats() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? stats : nil
    }

    static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (usage.xsu_used, usage.xsu_total)
    }

    // MARK: Disk — APFS "available for important usage" = real free space incl. purgeable

    static func diskUsage() -> (used: UInt64, total: UInt64)? {
        guard let values = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return (UInt64(max(0, Int64(total) - available)), UInt64(total))
    }

    // MARK: Network — cumulative rx/tx bytes over physical interfaces (en*)

    static func netCounters() -> (rx: UInt64, tx: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor = head
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en"), let data = ifa.pointee.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(counters.ifi_ibytes)
                tx += UInt64(counters.ifi_obytes)
            }
            cursor = ifa.pointee.ifa_next
        }
        return (rx, tx)
    }

    // MARK: GPU — Apple Silicon IOAccelerator performance stats

    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["PerformanceStatistics"] as? [String: Any] else { continue }
            for (key, value) in stats where key.contains("Utilization") {
                if let percent = (value as? NSNumber)?.doubleValue {
                    best = max(best ?? 0, percent)
                }
            }
        }
        return best
    }

    // MARK: Battery — nil on desktop Macs

    static func battery() -> (level: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let listRef = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else { return nil }
        let list = listRef as [CFTypeRef]
        for source in list {
            guard let raw = IOPSGetPowerSourceDescription(info, source) else { continue }
            let desc = raw.takeUnretainedValue() as? [String: Any]
            guard let type = desc?[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType,
                  let current = desc?[kIOPSCurrentCapacityKey] as? Int,
                  let maxCap = desc?[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
            let charging = (desc?[kIOPSIsChargingKey] as? Bool) ?? false
            return (current * 100 / maxCap, charging)
        }
        return nil
    }

    // MARK: Processes — PROC_PIDTASKALLINFO gives name + cumulative cpu time in one call

    struct ProcSample {
        let pid: pid_t
        let name: String
        let cpuNanoseconds: UInt64
    }

    static func processSamples() -> [ProcSample] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard written > 0 else { return [] }

        var samples: [ProcSample] = []
        samples.reserveCapacity(Int(written))
        for index in 0..<Int(written) {
            let pid = pids[index]
            guard pid > 0 else { continue }
            var info = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size else { continue }
            let name = withUnsafeBytes(of: info.pbsd.pbi_comm) {
                String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            samples.append(ProcSample(
                pid: pid,
                name: name,
                cpuNanoseconds: info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            ))
        }
        return samples
    }
}
