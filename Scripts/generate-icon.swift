import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates Assets/AppIcon.icns and Assets/AppIcon-1024.png.
// Usage: swift Scripts/generate-icon.swift [output-dir]

let root = CommandLine.arguments.dropFirst().first ?? "Assets"

func drawIcon(size: CGFloat) -> CGImage? {
    let s = size
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: Int(s), height: Int(s),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: s * 0.2237, cornerHeight: s * 0.2237, transform: nil))
    ctx.clip()

    // Background: dark navy gradient, top to bottom.
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(srgbRed: 0.11, green: 0.14, blue: 0.26, alpha: 1),
            CGColor(srgbRed: 0.04, green: 0.05, blue: 0.10, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])

    // Faint grid.
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05))
    ctx.setLineWidth(max(1, s * 0.004))
    for i in 1..<4 {
        let y = s * CGFloat(i) / 4
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: s, y: y))
    }
    for i in 1..<6 {
        let x = s * CGFloat(i) / 6
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: s))
    }
    ctx.strokePath()

    // Activity pulse (ECG-style polyline).
    let midY = s * 0.48
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: s * 0.08, y: midY))
    pulse.addLine(to: CGPoint(x: s * 0.28, y: midY))
    pulse.addLine(to: CGPoint(x: s * 0.36, y: s * 0.74))
    pulse.addLine(to: CGPoint(x: s * 0.46, y: s * 0.24))
    pulse.addLine(to: CGPoint(x: s * 0.54, y: midY))
    pulse.addLine(to: CGPoint(x: s * 0.62, y: midY))
    pulse.addLine(to: CGPoint(x: s * 0.68, y: s * 0.62))
    pulse.addLine(to: CGPoint(x: s * 0.76, y: midY))
    pulse.addLine(to: CGPoint(x: s * 0.92, y: midY))

    let green = CGColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: green.copy(alpha: 0.9))
    ctx.setStrokeColor(green)
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(pulse)
    ctx.strokePath()
    ctx.restoreGState()

    // Status dot, top right.
    ctx.setFillColor(green)
    ctx.fillEllipse(in: CGRect(x: s * 0.72, y: s * 0.72, width: s * 0.10, height: s * 0.10))

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "MonitorBar.icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create \(path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "MonitorBar.icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize \(path)"])
    }
}

do {
    let iconset = "\(root)/AppIcon.iconset"
    try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

    let sizes: [(String, CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, px) in sizes {
        guard let image = drawIcon(size: px) else {
            throw NSError(domain: "MonitorBar.icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Draw failed at \(Int(px))px"])
        }
        try writePNG(image, to: "\(iconset)/\(name).png")
    }

    guard let master = drawIcon(size: 1024) else {
        throw NSError(domain: "MonitorBar.icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Draw failed at 1024px"])
    }
    try writePNG(master, to: "\(root)/AppIcon-1024.png")

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset, "-o", "\(root)/AppIcon.icns"]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(domain: "MonitorBar.icon", code: 5, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }

    print("Wrote \(root)/AppIcon.icns and \(root)/AppIcon-1024.png")
} catch {
    FileHandle.standardError.write("generate-icon: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
