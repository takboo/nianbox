// Technical asset export from the approved imagegen master; no creative redrawing.
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift generate_app_icon.swift <master.png> <Assets.xcassets>")
}
let assets = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: appIcon, withIntermediateDirectories: true)

func png(size: Int, drawing: (NSRect) -> Void) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawing(NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try png(size: size) { source.draw(in: $0) }
        .write(to: appIcon.appendingPathComponent("icon_\(size).png"))
}
// The menu bar companion is drawn at runtime by MenuBarIconRenderer.
