// Draws the disk image's background: a plain field with an arrow pointing from where
// the app icon sits to where the Applications symlink sits. The icons themselves are
// Finder's, so this only has to supply what sits between them.
//
// Run: swift dmg/make-background.swift    (writes dmg/background.tiff)
//
// The window is sized to this image exactly, so changing these numbers means changing
// the bounds in scripts/release.sh to match.
import AppKit

let width = 640.0, height = 400.0

// Finder places an icon by the centre of its graphic, measured from the top of the
// window's content. The arrow is centred on the same line so it reads as pointing from
// one icon to the other -- this must stay equal to APP_Y/APPS_Y in build-dmg.sh.
let iconCentreFromTop = 180.0
let centreY = height - iconCentreFromTop
let arrowLeft = 258.0, arrowRight = 382.0
let shaftHeight = 14.0, headWidth = 34.0, headHeight = 40.0

func draw(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let arrow = NSBezierPath()
    let shaftTop = centreY + shaftHeight / 2, shaftBottom = centreY - shaftHeight / 2
    let headBase = arrowRight - headWidth
    arrow.move(to: NSPoint(x: arrowLeft, y: shaftBottom))
    arrow.line(to: NSPoint(x: headBase, y: shaftBottom))
    arrow.line(to: NSPoint(x: headBase, y: centreY - headHeight / 2))
    arrow.line(to: NSPoint(x: arrowRight, y: centreY))
    arrow.line(to: NSPoint(x: headBase, y: centreY + headHeight / 2))
    arrow.line(to: NSPoint(x: headBase, y: shaftTop))
    arrow.line(to: NSPoint(x: arrowLeft, y: shaftTop))
    arrow.close()
    NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
    arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
for scale in [1, 2] {
    let name = scale == 1 ? "background.png" : "background@2x.png"
    let data = draw(scale: scale).representation(using: .png, properties: [:])!
    try! data.write(to: here.appendingPathComponent(name))
}
print("wrote background.png and background@2x.png (\(Int(width))x\(Int(height)))")
