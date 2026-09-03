// Draws the app icon that Finder, Spotlight and the app switcher show. This is
// not the menu bar icon, which is an SF Symbol drawn in MenuBarController.
//
//   swiftc tools/render-icon.swift -o /tmp/render-icon && /tmp/render-icon
//
// Writes a master PNG, which then has to be resized into the ten entries of
// app/Assets.xcassets/AppIcon.appiconset. Kept in the repo so the icon can be
// changed later without reverse-engineering ten flattened PNGs.
//
// Note the output is 2048 square rather than 1024: lockFocus draws through the
// main display's backing scale, so on a retina Mac everything comes out at 2x.
import AppKit

// Apple's macOS icon grid: on a 1024 canvas the rounded plate is 824 square,
// centred, leaving the margin the system expects for shadow and alignment.
let canvas: CGFloat = 1024
let plateSize: CGFloat = 824
let cornerRadius: CGFloat = 185.4

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.setAllowsAntialiasing(true)

let plate = NSRect(
    x: (canvas - plateSize) / 2,
    y: (canvas - plateSize) / 2,
    width: plateSize,
    height: plateSize
)

// A near-black plate with a slight lift towards the top, so the icon reads as
// deliberate rather than flat, and stays legible on both light and dark
// Finder backgrounds.
let path = NSBezierPath(roundedRect: plate, xRadius: cornerRadius, yRadius: cornerRadius)
context.saveGState()
path.addClip()

let gradient = NSGradient(
    colors: [
        NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
    ]
)
gradient?.draw(in: plate, angle: -90)
context.restoreGState()

// A hairline inner edge, which is what keeps a dark icon from looking like a
// hole when it sits on a dark background.
context.saveGState()
NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
let edge = NSBezierPath(
    roundedRect: plate.insetBy(dx: 1.5, dy: 1.5),
    xRadius: cornerRadius,
    yRadius: cornerRadius
)
edge.lineWidth = 3
edge.stroke()
context.restoreGState()

guard
    let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 700, weight: .regular)
        )
else { exit(1) }

// Tint to white by drawing the glyph and filling through it.
let glyph = NSImage(size: symbol.size)
glyph.lockFocus()
let glyphRect = NSRect(origin: .zero, size: symbol.size)
symbol.draw(in: glyphRect)
NSColor.white.set()
glyphRect.fill(using: .sourceAtop)
glyph.unlockFocus()

// Fit inside 56% of the plate, preserving the glyph's own proportions.
let target = plateSize * 0.56
let scale = min(target / symbol.size.width, target / symbol.size.height)
let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)

glyph.draw(
    in: NSRect(
        x: (canvas - drawn.width) / 2,
        y: (canvas - drawn.height) / 2,
        width: drawn.width,
        height: drawn.height
    )
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { exit(1) }

try png.write(to: URL(fileURLWithPath: "/tmp/nota-icon-master.png"))
print("rendered \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
