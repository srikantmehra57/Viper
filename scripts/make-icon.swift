import AppKit

// Render the existing V mark as a native application icon at every macOS icon size.
let directory = URL(fileURLWithPath: ".build/Viper.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let shadow = NSBezierPath(roundedRect: NSRect(x: 99, y: 75, width: 850, height: 850), xRadius: 185, yRadius: 185)
        NSColor(srgbRed: 0.12, green: 0.15, blue: 0.12, alpha: 1).setFill()
        shadow.fill()
        let tile = NSBezierPath(roundedRect: NSRect(x: 74, y: 110, width: 840, height: 840), xRadius: 180, yRadius: 180)
        NSColor(srgbRed: 0.81, green: 0.94, blue: 0.81, alpha: 1).setFill()
        tile.fill()
        NSColor(srgbRed: 0.13, green: 0.16, blue: 0.13, alpha: 1).setStroke()
        tile.lineWidth = 24
        tile.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 660, weight: .black), .foregroundColor: NSColor(srgbRed: 0.13, green: 0.16, blue: 0.13, alpha: 1)]
        let mark = "V" as NSString
        let measured = mark.size(withAttributes: attributes)
        mark.draw(at: NSPoint(x: 494 - measured.width / 2, y: 540 - measured.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
