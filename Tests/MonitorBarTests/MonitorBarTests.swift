import XCTest
@testable import MonitorBarCore

final class LoadLevelTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(LoadLevel(percent: 0), .normal)
        XCTAssertEqual(LoadLevel(percent: 49.9), .normal)
        XCTAssertEqual(LoadLevel(percent: 50), .elevated)
        XCTAssertEqual(LoadLevel(percent: 79.9), .elevated)
        XCTAssertEqual(LoadLevel(percent: 80), .critical)
        XCTAssertEqual(LoadLevel(percent: 100), .critical)
    }
}

final class BusyPercentTests: XCTestCase {
    private func ticks(user: UInt32 = 0, system: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0) -> host_cpu_load_info {
        var info = host_cpu_load_info()
        info.cpu_ticks.0 = user
        info.cpu_ticks.1 = system
        info.cpu_ticks.2 = idle
        info.cpu_ticks.3 = nice
        return info
    }

    func testHalfBusy() {
        let prev = ticks(user: 100, system: 100, idle: 800)
        let now = ticks(user: 150, system: 150, idle: 900)
        XCTAssertEqual(Probes.busyPercent(from: prev, to: now), 50, accuracy: 0.001)
    }

    func testAllIdle() {
        let prev = ticks(idle: 100)
        let now = ticks(idle: 200)
        XCTAssertEqual(Probes.busyPercent(from: prev, to: now), 0)
    }

    func testZeroDelta() {
        let t = ticks(user: 10, idle: 10)
        XCTAssertEqual(Probes.busyPercent(from: t, to: t), 0)
    }

    func testCounterWraparound() {
        // Simulate a 32-bit-ish counter wrapping: previous > current.
        var prev = host_cpu_load_info()
        prev.cpu_ticks.0 = .max - 4 // user
        prev.cpu_ticks.3 = 0        // nice
        var now = host_cpu_load_info()
        now.cpu_ticks.0 = 5         // wrapped past max: delta = 10
        now.cpu_ticks.2 = 90        // idle delta = 90
        XCTAssertEqual(Probes.busyPercent(from: prev, to: now), 10, accuracy: 0.001)
    }
}

final class LabelTests: XCTestCase {
    @MainActor
    func testPreviewLabelFormat() {
        XCTAssertEqual(SystemMonitor.preview().label, "C23% M61%")
    }
}
