import AppKit
import Darwin
import SwiftUI

public extension LoadLevel {
    var color: Color {
        switch self {
        case .normal: return .green
        case .elevated: return .orange
        case .critical: return .red
        }
    }
}

private extension Double {
    var percent: String { formatted(.number.precision(.fractionLength(0))) + "%" }
    var rate: String { Int64(self).formatted(.byteCount(style: .binary)) + "/s" }
}

private extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

public struct PanelView: View {
    @ObservedObject public var monitor: SystemMonitor
    @State private var pendingKill: TopProcess?
    @State private var killError: String?

    public init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("CPU", value: monitor.cpuPercent?.percent ?? "--")
            LabeledContent("Memory", value: monitor.memPercent?.percent ?? "--")
            if let swap = monitor.swapPercent, swap > 0 {
                LabeledContent("Swap", value: swap.percent)
            }
            LabeledContent("Disk", value: monitor.diskPercent?.percent ?? "--")
            if let gpu = monitor.gpuPercent {
                LabeledContent("GPU", value: gpu.percent)
            }
            if let rx = monitor.netRxPerSec, let tx = monitor.netTxPerSec {
                LabeledContent("Network", value: "↓\(rx.rate)  ↑\(tx.rate)")
            }
            LabeledContent("Thermal", value: monitor.thermal.displayName)
            if let battery = monitor.battery {
                LabeledContent("Battery", value: "\(battery.level)%\(battery.charging ? " (charging)" : "")")
            }

            if !monitor.topProcesses.isEmpty {
                Divider()
                Text("Top CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(monitor.topProcesses) { process in
                    LabeledContent {
                        HStack {
                            Text(process.cpuPercent.percent).monospacedDigit()
                            Button("Terminate", systemImage: "xmark.circle") {
                                pendingKill = process
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Send SIGTERM to \(process.name) (pid \(process.pid))")
                        }
                    } label: {
                        Text(process.name.isEmpty ? "pid \(process.pid)" : process.name)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }

            Divider()
            Picker("Refresh", selection: $monitor.interval) {
                Text("1s").tag(Duration.seconds(1))
                Text("1.5s").tag(Duration.milliseconds(1500))
                Text("2s").tag(Duration.seconds(2))
                Text("5s").tag(Duration.seconds(5))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            HStack {
                Button("Activity Monitor") {
                    NSWorkspace.shared.openApplication(
                        at: URL(filePath: "/System/Applications/Utilities/Activity Monitor.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
                Spacer()
                Button("Quit", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .alert(
            "Terminate process?",
            isPresented: Binding(
                get: { pendingKill != nil },
                set: { if !$0 { pendingKill = nil } }
            ),
            presenting: pendingKill
        ) { process in
            Button("Terminate \(process.name)", role: .destructive) {
                if !monitor.terminate(process) {
                    killError = String(cString: strerror(errno))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { process in
            Text("SIGTERM will be sent to pid \(process.pid).")
        }
        .alert(
            "Could not terminate process",
            isPresented: Binding(
                get: { killError != nil },
                set: { if !$0 { killError = nil } }
            ),
            presenting: killError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { detail in
            Text("SIGTERM failed: \(detail). Processes owned by other users require elevated privileges.")
        }
    }
}
