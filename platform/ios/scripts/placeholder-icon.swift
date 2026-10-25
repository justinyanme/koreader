// usage: swift platform/ios/scripts/placeholder-icon.swift <AppIcon.appiconset dir>
// Renders the placeholder app icon: a near-black square with a white book.
// Opaque (no alpha), as App Store Connect requires. Adapted from justoodoo; replaced by the real icon later.

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let ink = NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255, alpha: 1)
let px = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
    samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: px * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let side = CGFloat(px)
ink.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
let config = NSImage.SymbolConfiguration(pointSize: side * 0.45, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let glyph = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let size = glyph.size
glyph.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                      width: size.width, height: size.height))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("icon-\(px).png"))
