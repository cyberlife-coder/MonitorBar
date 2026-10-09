import AppKit
import MonitorBarCore
import SwiftUI

// Renders PanelView with fixed sample data into a PNG for the README.
// A real (offscreen) NSWindow is used so buttons and SF Symbols resolve.
// Usage: swift run SnapshotTool [output.png]
let outputPath = CommandLine.arguments.dropFirst().first ?? "Docs/screenshot.png"

UserDefaults.standard.register(defaults: ["AppleLanguages": ["en"]])

let app = NSApplication.shared
app.appearance = NSAppearance(named: .aqua)

let png: Data? = MainActor.assumeIsolated {
    let root = PanelView(monitor: .preview()).environment(\.locale, Locale(identifier: "en_US"))
    let view = NSHostingView(rootView: root)
    let window = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 480),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.orderBack(nil)

    let size = view.fittingSize
    window.setContentSize(size)
    view.frame = NSRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()

    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    window.orderOut(nil)
    return rep.representation(using: .png, properties: [:])
}

guard let png else {
    FileHandle.standardError.write("Failed to render panel.\n".data(using: .utf8)!)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: url)
print("Wrote \(outputPath)")
