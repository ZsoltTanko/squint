import AppKit

// Squint's app icon: a half-closed eye on a dark rounded square.
// Drawn in a 1024-point design space and rendered at each size macOS needs.
//
// Usage: swift bin/make-app-icon.swift Squint/Assets.xcassets/AppIcon.appiconset
//        swift bin/make-app-icon.swift --preview PREVIEW.png

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    ctx.saveGState()
    ctx.scaleBy(x: s, y: s)

    // Rounded-square body on the standard macOS icon grid, with a soft drop shadow.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x1B1E25).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x3A4050), ending: color(0x16181E))!.draw(in: body, angle: -90)

    // Eye: an almond from x=222 to x=802, centered at y=500.
    let cx: CGFloat = 512, cy: CGFloat = 500, halfW: CGFloat = 290
    let almond = NSBezierPath()
    almond.move(to: NSPoint(x: cx - halfW, y: cy))
    almond.curve(to: NSPoint(x: cx + halfW, y: cy),
                 controlPoint1: NSPoint(x: cx - 150, y: cy + 250),
                 controlPoint2: NSPoint(x: cx + 150, y: cy + 250))
    almond.curve(to: NSPoint(x: cx - halfW, y: cy),
                 controlPoint1: NSPoint(x: cx + 150, y: cy - 250),
                 controlPoint2: NSPoint(x: cx - 150, y: cy - 250))
    almond.close()

    NSGraphicsContext.saveGraphicsState()
    almond.addClip()
    // Sclera.
    color(0xF4F3EF).setFill()
    almond.fill()
    // Iris, pupil and highlight, sitting low in the eye.
    let irisCenter = NSPoint(x: cx, y: cy - 20)
    NSGradient(starting: color(0x9A86FF), ending: color(0x5B3FD9))!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: irisCenter.x - 135, y: irisCenter.y - 135, width: 270, height: 270)), angle: -90)
    color(0x111217).setFill()
    NSBezierPath(ovalIn: NSRect(x: irisCenter.x - 60, y: irisCenter.y - 60, width: 120, height: 120)).fill()
    color(0xFFFFFF, 0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: irisCenter.x + 22, y: irisCenter.y - 58, width: 40, height: 40)).fill()
    // Upper lid lowered past the middle: that's the squint.
    let lidEdgeY = cy + 20
    let lid = NSBezierPath()
    lid.move(to: NSPoint(x: cx - halfW - 10, y: cy + 400))
    lid.line(to: NSPoint(x: cx - halfW - 10, y: cy))
    lid.curve(to: NSPoint(x: cx + halfW + 10, y: cy),
              controlPoint1: NSPoint(x: cx - 120, y: lidEdgeY - 40),
              controlPoint2: NSPoint(x: cx + 120, y: lidEdgeY - 40))
    lid.line(to: NSPoint(x: cx + halfW + 10, y: cy + 400))
    lid.close()
    NSGradient(starting: color(0x6A7288), ending: color(0x4A5063))!.draw(in: lid, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Lid edge and almond outline.
    let lidEdge = NSBezierPath()
    lidEdge.move(to: NSPoint(x: cx - halfW, y: cy))
    lidEdge.curve(to: NSPoint(x: cx + halfW, y: cy),
                  controlPoint1: NSPoint(x: cx - 120, y: lidEdgeY - 40),
                  controlPoint2: NSPoint(x: cx + 120, y: lidEdgeY - 40))
    lidEdge.lineWidth = 26
    lidEdge.lineCapStyle = .round
    color(0x0E0F13).setStroke()
    lidEdge.stroke()
    almond.lineWidth = 26
    almond.lineJoinStyle = .round
    almond.stroke()

    ctx.restoreGState()
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: NSGraphicsContext.current!.cgContext, size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
if args.count == 3, args[1] == "--preview" {
    // Large icon plus actual small sizes on light and dark backgrounds.
    let sheet = NSImage(size: NSSize(width: 1100, height: 560), flipped: false) { _ in
        color(0xECECEC).setFill(); NSRect(x: 0, y: 0, width: 1100, height: 280).fill()
        color(0x1E1E1E).setFill(); NSRect(x: 0, y: 280, width: 1100, height: 280).fill()
        NSImage(cgImage: render(pixels: 512).cgImage!, size: NSSize(width: 512, height: 512))
            .draw(in: NSRect(x: 24, y: 24, width: 512, height: 512))
        for y in [60.0, 340.0] {
            var x: CGFloat = 580
            for pt in [128, 64, 32, 16] {
                let img = NSImage(cgImage: render(pixels: pt * 2).cgImage!, size: NSSize(width: pt, height: pt))
                img.draw(in: NSRect(x: x, y: y, width: CGFloat(pt), height: CGFloat(pt)))
                x += CGFloat(pt) + 40
            }
        }
        return true
    }
    let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    writePNG(rep, to: args[2])
} else if args.count == 2 {
    // File names match the appiconset's Contents.json: icon_<points>x<points>[@2x].png.
    for points in [16, 32, 128, 256, 512] {
        writePNG(render(pixels: points), to: "\(args[1])/icon_\(points)x\(points).png")
        writePNG(render(pixels: points * 2), to: "\(args[1])/icon_\(points)x\(points)@2x.png")
    }
} else {
    print("usage: swift bin/make-app-icon.swift APPICONSET_DIR | --preview PREVIEW.png")
}
