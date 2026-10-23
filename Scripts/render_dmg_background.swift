import AppKit
import Foundation
let output = CommandLine.arguments[1]
let scale = Int(CommandLine.arguments[2])!
precondition([1, 2].contains(scale))
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 700 * scale, pixelsHigh: 460 * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform(); transform.scale(by: CGFloat(scale)); transform.concat()
NSColor(calibratedRed: 0.965, green: 0.949, blue: 0.922, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 700, height: 460).fill()
let ink = NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.22, alpha: 1)
func centered(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    (text as NSString).draw(in: NSRect(x: 30, y: y, width: 640, height: size * 1.7),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}
centered("念匣 · NianBox", y: 358, size: 28, weight: .semibold, color: ink)
centered("Capture first, organize later.", y: 326, size: 14, weight: .regular, color: ink.withAlphaComponent(0.65))
centered("将 NianBox 拖入应用程序", y: 70, size: 17, weight: .medium, color: ink)
centered("Drag NianBox to Applications, then open it from Applications.", y: 40, size: 12, weight: .regular, color: ink.withAlphaComponent(0.65))
let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 310, y: 217)); arrow.line(to: NSPoint(x: 390, y: 217))
arrow.move(to: NSPoint(x: 375, y: 232)); arrow.line(to: NSPoint(x: 390, y: 217)); arrow.line(to: NSPoint(x: 375, y: 202))
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.70, green: 0.43, blue: 0.34, alpha: 1).setStroke(); arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
bitmap.size = NSSize(width: 700, height: 460)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
