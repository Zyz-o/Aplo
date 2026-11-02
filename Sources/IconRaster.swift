import AppKit

/// Serial worker owns each context and image until immutable handoff to the main actor.
enum IconRaster {
    static func pixelSize(points: CGFloat, scale: CGFloat) -> Int {
        // Include hover magnification, quantize to avoid a new bitmap at every slider step.
        min(512, max(64, Int(ceil(points * 1.38 * scale / 64)) * 64))
    }
    static func load(path: String, pixels: Int) -> NSImage {
        let source = NSWorkspace.shared.icon(forFile: path)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context; context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
                    operation: .copy, fraction: 1)
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixels, height: pixels)); image.addRepresentation(bitmap)
        return image
    }
}

final class CachedApplicationIcon: NSObject {
    let image: NSImage
    let pixels: Int
    init(image: NSImage, pixels: Int) { self.image = image; self.pixels = pixels }
}
