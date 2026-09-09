// Renders the app icon set: the in-app brand mark (green waveform on the dark
// theme) on a standard macOS plate. Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let accent = NSColor(srgbRed: 0.66, green: 0.86, blue: 0.42, alpha: 1)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    // Apple's template: an 824 pt plate centred on a 1024 pt canvas.
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: plate, xRadius: 186 * s, yRadius: 186 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.17, green: 0.19, blue: 0.22, alpha: 1),
                        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)])!.draw(in: shape, angle: -90)
    shape.addClip()
    let ring = NSBezierPath(ovalIn: plate.insetBy(dx: 132 * s, dy: 132 * s)); ring.lineWidth = 12 * s
    accent.withAlphaComponent(0.2).setStroke(); ring.stroke()
    let glow = NSShadow(); glow.shadowColor = accent.withAlphaComponent(0.5); glow.shadowBlurRadius = 46 * s; glow.set()
    let configuration = NSImage.SymbolConfiguration(pointSize: 400 * s, weight: .semibold).applying(.init(paletteColors: [accent]))
    let symbol = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
    let size = symbol.size
    symbol.draw(in: NSRect(x: plate.midX - size.width / 2, y: plate.midY - size.height / 2, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                       ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(pixels).write(to: output.appendingPathComponent("icon_\(name).png"))
}
