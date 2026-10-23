import AppKit

/// Runtime vector companion to the approved drawer artwork. All holes remain transparent.
enum MenuBarIconRenderer {
    static func image(for frame: MenuBarIconFrame) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for scale in [1, 2] {
            let pixels = 18 * scale
            let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(pixels))
            context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
            draw(frame, in: context)
            let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    private static func rounded(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        c.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        c.fillPath()
    }

    private static func circle(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        c.fillEllipse(in: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r))
    }

    private static func line(_ c: CGContext, _ points: [CGPoint], _ width: CGFloat) {
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.beginPath()
        for (index, point) in points.enumerated() {
            if index == 0 { c.move(to: point) } else { c.addLine(to: point) }
        }
        c.strokePath()
    }

    private static func note(_ c: CGContext, y: CGFloat, angle: CGFloat, dot: Bool = true) {
        c.saveGState()
        c.translateBy(x: 9.25, y: 7.1)
        c.rotate(by: angle)
        c.translateBy(x: -9.25, y: -7.1)
        c.beginPath()
        c.move(to: CGPoint(x: 6.15, y: y+0.3))
        c.addQuadCurve(to: CGPoint(x: 6.6, y: y), control: CGPoint(x: 6.15, y: y))
        for point in [CGPoint(x: 10.55, y: y), CGPoint(x: 13.05, y: y+2.5),
                      CGPoint(x: 13.05, y: y+9.8), CGPoint(x: 6.15, y: y+9.8)] {
            c.addLine(to: point)
        }
        c.closePath()
        c.fillPath()
        c.setBlendMode(.clear)
        line(c, [CGPoint(x: 10.5, y: y+0.9), CGPoint(x: 10.5, y: y+2.6), CGPoint(x: 12.25, y: y+2.6)], 0.8)
        if dot { circle(c, 8.55, y+4.8, 0.72) }
        c.restoreGState()
    }

    private static func draw(_ f: MenuBarIconFrame, in c: CGContext) {
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        c.setStrokeColor(CGColor(gray: 0, alpha: 1))
        let b = f.bodyY
        rounded(c, 1.1, 6.1+b, 15.8, 10.7, 2.85)
        c.setBlendMode(.clear)
        rounded(c, 2.35, 7.35+b, 13.3, 6.6, 1.5)
        c.setBlendMode(.normal)
        if f.mark == .connectionFailure {
            rounded(c, 2.5, 2.8, 3.7, 3.7, 0.85)
            line(c, [CGPoint(x: 1.3, y: 4.65), CGPoint(x: 2.5, y: 4.65)], 1.25)
            line(c, [CGPoint(x: 6.2, y: 3.65), CGPoint(x: 7.3, y: 3.65)], 1.1)
            line(c, [CGPoint(x: 6.2, y: 5.15), CGPoint(x: 7.3, y: 5.15)], 1.1)
            rounded(c, 11.8, 1.2, 3.7, 3.7, 0.85)
            line(c, [CGPoint(x: 15.5, y: 3.05), CGPoint(x: 16.7, y: 3.05)], 1.25)
            line(c, [CGPoint(x: 10.7, y: 2.05), CGPoint(x: 11.8, y: 2.05)], 1.1)
            line(c, [CGPoint(x: 10.7, y: 3.55), CGPoint(x: 11.8, y: 3.55)], 1.1)
        } else if f.mark == .conflict {
            c.saveGState(); c.translateBy(x: -1.3, y: 0.55); c.scaleBy(x: 0.72, y: 1)
            note(c, y: 1.3, angle: -0.22, dot: false); c.restoreGState()
            c.saveGState(); c.translateBy(x: 4.1, y: 0.55); c.scaleBy(x: 0.72, y: 1)
            note(c, y: 1.3, angle: 0.22, dot: false); c.restoreGState()
        } else { note(c, y: f.paperY, angle: f.paperAngle) }
        c.beginPath()
        c.move(to: CGPoint(x: 1.1, y: 8.5+b))
        c.addQuadCurve(to: CGPoint(x: 5.6, y: 8.6+b), control: CGPoint(x: 3.5, y: 8.3+b))
        c.addQuadCurve(to: CGPoint(x: 12.4, y: 8.6+b), control: CGPoint(x: 9, y: 10.5+b))
        c.addQuadCurve(to: CGPoint(x: 16.9, y: 8.5+b), control: CGPoint(x: 15, y: 8.3+b))
        c.addLine(to: CGPoint(x: 16.9, y: 13.9+b))
        c.addQuadCurve(to: CGPoint(x: 14, y: 16.8+b), control: CGPoint(x: 16.9, y: 16.8+b))
        c.addLine(to: CGPoint(x: 4, y: 16.8+b))
        c.addQuadCurve(to: CGPoint(x: 1.1, y: 13.9+b), control: CGPoint(x: 1.1, y: 16.8+b))
        c.closePath(); c.fillPath()
        c.setBlendMode(.clear)
        line(c, [CGPoint(x: 3, y: 8.1+b), CGPoint(x: 5.6, y: 8.1+b), CGPoint(x: 7.2, y: 8.9+b),
            CGPoint(x: 10.8, y: 8.9+b), CGPoint(x: 12.4, y: 8.1+b), CGPoint(x: 15, y: 8.1+b)], 0.85)
        if f.mark == .saveFailure {
            line(c, [CGPoint(x: 6.55, y: 10.9), CGPoint(x: 11.45, y: 15.4)], 1.5)
            line(c, [CGPoint(x: 6.55, y: 15.4), CGPoint(x: 11.45, y: 10.9)], 1.5)
        } else { circle(c, 9, 13.1+b, 1.25) }
        c.setBlendMode(.normal)
        if f.mark == .waiting {
            c.setBlendMode(.clear); circle(c, 15.15, 4.1, 1.9)
            c.setBlendMode(.normal); circle(c, 15.15, 4.1, 1)
        } else if [.syncing, .synced, .offline].contains(f.mark) {
            c.setBlendMode(.clear); circle(c, 14.8, 3.35, 3.2)
            c.setBlendMode(.normal)
            if f.mark == .syncing {
                c.setLineCap(.round); c.setLineWidth(1.2)
                c.addArc(center: CGPoint(x: 14.8, y: 3.35), radius: 2.05,
                    startAngle: f.rotation, endAngle: f.rotation + .pi * 1.45, clockwise: false)
                c.strokePath()
            } else {
                circle(c, 14.8, 3.35, 2.5); c.setBlendMode(.clear)
                if f.mark == .synced {
                    line(c, [CGPoint(x: 13.5, y: 3.35), CGPoint(x: 14.35, y: 4.15), CGPoint(x: 16, y: 2.5)], 0.85)
                } else {
                    line(c, [CGPoint(x: 14.05, y: 2.35), CGPoint(x: 14.05, y: 4.25)], 0.68)
                    line(c, [CGPoint(x: 15.5, y: 2.35), CGPoint(x: 15.5, y: 4.25)], 0.68)
                }
            }
        }
    }
}
