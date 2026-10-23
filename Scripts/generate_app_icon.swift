// Technical asset export from the approved imagegen master; no creative redrawing.
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift generate_app_icon.swift <master.png> <Assets.xcassets>")
}
let assets = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
let menuIcon = assets.appendingPathComponent("MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: appIcon, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuIcon, withIntermediateDirectories: true)

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
// Reduced monochrome companion to the full 3D application artwork.
for scale in [1, 2] {
    try png(size: 18 * scale) { _ in
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(scale))
        transform.concat()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 5, y: 7, width: 8, height: 10), xRadius: 1.5, yRadius: 1.5).fill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 10), xRadius: 3, yRadius: 3).fill()
        let opening = NSBezierPath()
        opening.move(to: NSPoint(x: 2.5, y: 10))
        opening.line(to: NSPoint(x: 6.3, y: 10))
        opening.curve(to: NSPoint(x: 9, y: 8.5), controlPoint1: NSPoint(x: 7, y: 8.5), controlPoint2: NSPoint(x: 7.8, y: 8.5))
        opening.curve(to: NSPoint(x: 11.7, y: 10), controlPoint1: NSPoint(x: 10.2, y: 8.5), controlPoint2: NSPoint(x: 11, y: 8.5))
        opening.line(to: NSPoint(x: 15.5, y: 10))
        NSGraphicsContext.current!.cgContext.setBlendMode(.clear)
        opening.lineWidth = 1.2
        opening.stroke()
    }.write(to: menuIcon.appendingPathComponent("menu-\(scale)x.png"))
}
let menuContents: [String: Any] = ["images": [
    ["filename": "menu-1x.png", "idiom": "mac", "scale": "1x"],
    ["filename": "menu-2x.png", "idiom": "mac", "scale": "2x"]],
    "info": ["author": "xcode", "version": 1], "properties": ["template-rendering-intent": "template"]]
try JSONSerialization.data(withJSONObject: menuContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: menuIcon.appendingPathComponent("Contents.json"))
