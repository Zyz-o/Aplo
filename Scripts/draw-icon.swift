import AppKit
import Foundation

// Package the user's original photograph as a macOS icon, without retouching it.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: sourceURL), source.size.width > 0, source.size.height > 0 else {
    fatalError("Cannot read icon photograph")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let side = min(source.size.width, source.size.height)
let crop = NSRect(x: (source.size.width - side) / 2, y: (source.size.height - side) / 2,
                  width: side, height: side)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let p = CGFloat(pixels)
        let bounds = NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88)
        NSBezierPath(roundedRect: bounds, xRadius: p * 0.20, yRadius: p * 0.20).addClip()
        source.draw(in: bounds, from: crop, operation: .sourceOver, fraction: 1,
                    respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
