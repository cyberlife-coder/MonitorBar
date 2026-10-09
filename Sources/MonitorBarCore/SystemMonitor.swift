import Darwin
import Foundation

public struct TopProcess: Identifiable {
    let pid: pid_t
    let name: String
    let cpuPercent: Double
    public var id: pid_t { pid }
}

public struct BatteryStatus {
    let level: Int
    let charging: Bool
}

public enum LoadLevel {
    case normal, elevated, critical

    init(percent: Double) {
        if percent >= 80 { self = .critical }
        else if percent >= 50 { self = .elevated }
        else { self = .normal }
    }
}

@MainActor
public final class SystemMonitor: ObservableObject {
    public static let shared = SystemMonitor()

    @Published public private(set) var cpuPercent: Double?
    @Published public private(set) var memPercent: Double?
    @Published public private(set) var diskPercent: Double?
    @Published public private(set) var swapPercent: Double?
    @Published public private(set) var gpuPercent: Double?
    @Published public private(set) var netRxPerSec: Double?
    @Published public private(set) var netTxPerSec: Double?
    @Published public private(set) var battery: BatteryStatus?
    @Published public private(set) var thermal: ProcessInfo.ThermalState = .nominal
    @Published public private(set) var topProcesses: [TopProcess] = []

    @Published public var interval: Duration = .milliseconds(1500)

    private var previousTicks: host_cpu_load_info?
    private var previousNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var previousProcTimes: [pid_t: UInt64] = [:]
    private var previousProcAt: Date?
    private var pollingTask: Task<Void, Never>?

    private let pageSize: UInt64
    private let totalMemory: UInt64

    public var label: String {
        func format(_ percent: Double?) -> String {
            percent.map { "\(Int($0.rounded()))" } ?? "--"
        }
        return "C\(format(cpuPercent))% M\(format(memPercent))%"
    }

    public var loadLevel: LoadLevel {
        LoadLevel(percent: max(cpuPercent ?? 0, memPercent ?? 0))
    }

    private nonisolated init() {
        pageSize = UInt64(Probes.sysctlInt64("hw.pagesize") ?? Int64(vm_page_size))
        totalMemory = UInt64(Probes.sysctlInt64("hw.memsize") ?? 0)
    }

    public func start() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.refresh()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    private func refresh() {
        sampleCPU()
        sampleMemory()
        sampleDiskAndSwap()
        sampleNetwork()
        sampleProcesses()
        gpuPercent = Probes.gpuUtilization()
        battery = Probes.battery().map(BatteryStatus.init)
        thermal = ProcessInfo.processInfo.thermalState
    }

    private func sampleCPU() {
        guard let ticks = Probes.cpuTicks() else { return }
        if let prev = previousTicks {
            cpuPercent = Probes.busyPercent(from: prev, to: ticks)
        }
        previousTicks = ticks
    }

    private func sampleMemory() {
        guard let stats = Probes.vmStats(), totalMemory > 0 else { return }
        let usedPages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        memPercent = min(max(Double(usedPages * pageSize) / Double(totalMemory) * 100, 0), 100)
    }

    private func sampleDiskAndSwap() {
        if let disk = Probes.diskUsage(), disk.total > 0 {
            diskPercent = Double(disk.used) / Double(disk.total) * 100
        }
        swapPercent = Probes.swapUsage().map { $0.total > 0 ? Double($0.used) / Double($0.total) * 100 : 0 }
    }

    private func sampleNetwork() {
        guard let counters = Probes.netCounters() else { return }
        let now = Date()
        defer { previousNet = (counters.rx, counters.tx, now) }
        guard let prev = previousNet else { return }
        let dt = now.timeIntervalSince(prev.at)
        guard dt > 0 else { return }
        netRxPerSec = Double(counters.rx &- prev.rx) / dt
        netTxPerSec = Double(counters.tx &- prev.tx) / dt
    }

    private func sampleProcesses() {
        let samples = Probes.processSamples()
        let now = Date()
        defer {
            previousProcAt = now
            previousProcTimes = Dictionary(samples.map { ($0.pid, $0.cpuNanoseconds) }, uniquingKeysWith: { a, _ in a })
        }
        guard let prevAt = previousProcAt else { return }
        let dt = now.timeIntervalSince(prevAt)
        guard dt > 0 else { return }
        topProcesses = Array(samples.compactMap { sample in
            guard let previous = previousProcTimes[sample.pid],
                  sample.cpuNanoseconds > previous else { return nil }
            let percent = Double(sample.cpuNanoseconds - previous) / (dt * 1e9) * 100
            guard percent > 0.5 else { return nil }
            return TopProcess(pid: sample.pid, name: sample.name, cpuPercent: percent)
        }
        .sorted(using: KeyPathComparator(\.cpuPercent, order: .reverse))
        .prefix(5))
    }

    public func terminate(_ process: TopProcess) -> Bool {
        kill(process.pid, SIGTERM) == 0
    }
}

extension SystemMonitor {
    /// Fixed sample values used by previews and the screenshot generator.
    public static func preview() -> SystemMonitor {
        let monitor = SystemMonitor()
        monitor.cpuPercent = 23
        monitor.memPercent = 61
        monitor.swapPercent = 4
        monitor.diskPercent = 42
        monitor.gpuPercent = 18
        monitor.netRxPerSec = 1_400_000
        monitor.netTxPerSec = 320_000
        monitor.battery = BatteryStatus(level: 78, charging: true)
        monitor.thermal = .nominal
        monitor.topProcesses = [
            TopProcess(pid: 421, name: "kernel_task", cpuPercent: 12.3),
            TopProcess(pid: 132, name: "WindowServer", cpuPercent: 8.1),
            TopProcess(pid: 8810, name: "Safari", cpuPercent: 5.4),
            TopProcess(pid: 903, name: "spotlightknowledged", cpuPercent: 2.9),
            TopProcess(pid: 214, name: "mds_stores", cpuPercent: 1.7),
        ]
        return monitor
    }
}
