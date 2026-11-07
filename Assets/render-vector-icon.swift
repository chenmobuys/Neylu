import AppKit

// Keep every Apple iconset slot, rendered directly from the approved SVG.
// Reduce RGB to five-bit steps before PNG encoding. Alpha stays at eight bits:
// this removes tiny gradient/dither variations without changing shape or opacity.
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: render-vector-icon.swift source.svg destination.iconset")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Cannot allocate icon bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        if let bytes = bitmap.bitmapData {
            for row in 0..<pixels {
                for column in 0..<pixels {
                    let offset = row * bitmap.bytesPerRow + column * 4
                    let alpha = Int(bytes[offset + 3])
                    for component in 0..<3 {
                        let value = Int(bytes[offset + component])
                        bytes[offset + component] = UInt8(min(alpha, ((value + 4) / 8) * 8))
                    }
                }
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Cannot encode icon bitmap")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
