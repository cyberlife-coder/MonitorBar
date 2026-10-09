import AppKit
import MonitorBarCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SystemMonitor.shared.start()
    }
}

@main
struct MonitorBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = SystemMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            Text(monitor.label)
                .monospaced()
                .foregroundStyle(monitor.loadLevel.color)
        }
        .menuBarExtraStyle(.window)
    }
}
