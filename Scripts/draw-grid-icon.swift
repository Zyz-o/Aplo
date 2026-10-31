import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let bounds = NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88)
        let background = NSBezierPath(roundedRect: bounds, xRadius: p * 0.205, yRadius: p * 0.205)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.61, blue: 0.64, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.32, blue: 0.43, alpha: 1))!
        gradient.draw(in: background, angle: -65)
        for row in 0..<2 {
            for column in 0..<2 {
                let tile = NSRect(x: p * (0.245 + CGFloat(column) * 0.285), y: p * (0.245 + CGFloat(row) * 0.285), width: p * 0.225, height: p * 0.225)
                NSColor.white.withAlphaComponent(row == 1 && column == 1 ? 0.63 : 0.96).setFill()
                NSBezierPath(roundedRect: tile, xRadius: p * 0.052, yRadius: p * 0.052).fill()
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot render icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
