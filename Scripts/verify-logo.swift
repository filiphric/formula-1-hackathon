import AppKit

// Run against the built macOS app to catch missing/blank assets and lost transparency.
guard CommandLine.arguments.count == 2,
      let bundle = Bundle(path: CommandLine.arguments[1]),
      let image = bundle.image(forResource: "F1Logo") else {
    fatalError("The built app must bundle the official F1Logo image")
}
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 656, pixelsHigh: 164,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: 656, height: 164))
NSGraphicsContext.restoreGraphicsState()
var redPixels = 0
var transparentPixels = 0
for y in 0..<164 {
    for x in 0..<656 {
        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        if color.alphaComponent < 0.01 { transparentPixels += 1 }
        if color.alphaComponent > 0.9 && color.redComponent > 0.8 && color.greenComponent < 0.1 && color.blueComponent < 0.1 {
            redPixels += 1
        }
    }
}
// The official mark is wide, red and transparent; a square padded favicon or blank
// rendition must not pass as the header artwork.
precondition(image.size.width / image.size.height > 3.9 && image.size.width / image.size.height < 4.1,
             "The logo must retain its wide proportions without square padding")
precondition(redPixels > 30_000, "The logo must render visible F1 red artwork")
precondition(transparentPixels > 30_000, "The logo must retain a transparent background")
print("PASS: bundled F1 logo renders red with transparency and correct proportions")
