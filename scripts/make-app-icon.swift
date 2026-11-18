import AppKit

// Original vector artwork rendered with system APIs; no image tooling dependency.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(srgbRed: 0.26, green: 0.36, blue: 0.98, alpha: 1),
            ending: NSColor(srgbRed: 0.57, green: 0.24, blue: 0.89, alpha: 1))!.draw(in: tile, angle: 55)
        NSColor.white.withAlphaComponent(0.24).setStroke(); tile.lineWidth = 4; tile.stroke()
        for row in 0..<3 { for column in 0..<3 {
            let rect = NSRect(x: 232 + column * 202, y: 232 + row * 202, width: 156, height: 156)
            NSColor.white.withAlphaComponent(row == 2 && column == 2 ? 0.65 : 0.96).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36).fill()
        } }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
