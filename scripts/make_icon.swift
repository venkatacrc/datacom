// Draws the app icon (three rising bars on indigo, the tallest lit) and writes an .iconset
// folder for iconutil, or with --web the PNGs for the web app (icon-192/512 plus a
// full-bleed maskable-512 for Android).
// Usage: swift scripts/make_icon.swift OUT.iconset
//        swift scripts/make_icon.swift --web web/icons
import AppKit

enum Style { case mac, web, maskable }

let web = CommandLine.arguments[1] == "--web"
let out = URL(fileURLWithPath: CommandLine.arguments[web ? 2 : 1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int, _ style: Style = .mac) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: the tile is inset ~10% with a ~22% corner radius. Android crops
    // maskable icons to its own shape, keeping only the central 80% circle.
    let inset: CGFloat = style == .mac ? 0.1 : style == .web ? 0.02 : 0
    let tile = NSRect(x: s * inset, y: s * inset, width: s * (1 - 2 * inset), height: s * (1 - 2 * inset))
    let radius = style == .maskable ? 0 : tile.width * 0.225
    NSGradient(colors: [
        NSColor(red: 0.42, green: 0.40, blue: 0.98, alpha: 1),
        NSColor(red: 0.22, green: 0.18, blue: 0.70, alpha: 1),
    ])!.draw(in: NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius), angle: -90)

    let span = (style == .maskable ? s * 0.44 : tile.width * 0.54)
    let gap = span * 0.1
    let width = (span - 2 * gap) / 3
    let left = tile.midX - span / 2
    let bottom = tile.midY - span / 2
    let heights: [CGFloat] = [0.42, 0.7, 1.0]
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.025
    for (i, h) in heights.enumerated() {
        let lit = i == 2
        let rect = NSRect(x: left + CGFloat(i) * (width + gap), y: bottom, width: width, height: span * h)
        NSGraphicsContext.saveGraphicsState()
        if lit { shadow.set() }
        NSColor(red: 1.0, green: 0.98, blue: 0.92, alpha: lit ? 1 : 0.5 + 0.2 * CGFloat(i)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: width * 0.22, yRadius: width * 0.22).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if web {
    try render(192, .web).write(to: out.appendingPathComponent("icon-192.png"))
    try render(512, .web).write(to: out.appendingPathComponent("icon-512.png"))
    try render(512, .maskable).write(to: out.appendingPathComponent("maskable-512.png"))
} else {
    for size in [16, 32, 128, 256, 512] {
        try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
        try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
