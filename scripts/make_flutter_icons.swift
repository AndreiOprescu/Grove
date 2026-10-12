import AppKit

// Draws the app icon of the Flutter app ("Night sprout": a cream sprout on a
// dark green tile) and writes the icon files of the 4 systems under app/.
//
// Run it again only when the logo changes, from the root of the repo:
//   swift scripts/make_flutter_icons.swift
// It needs no package. `app/test/app_icons_test.dart` checks the files.

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

/// The three shapes of the tile.
enum Shape {
    /// macOS: a rounded tile with a clear edge around it and a soft shadow.
    case mac
    /// Windows and Android: the rounded tile fills the picture.
    case rounded
    /// iOS: a full square with no alpha. The system rounds it.
    case square
}

let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)

/// An almond leaf from its base `a` to its tip `b`; `w` is how far it bulges.
func leaf(_ a: NSPoint, _ b: NSPoint, _ w: CGFloat) -> NSBezierPath {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = (dx * dx + dy * dy).squareRoot()
    let px = -dy / len, py = dx / len
    func at(_ t: CGFloat, _ off: CGFloat) -> NSPoint { pt(a.x + dx * t + px * off, a.y + dy * t + py * off) }
    let p = NSBezierPath()
    p.move(to: a)
    p.curve(to: b, controlPoint1: at(0.25, w), controlPoint2: at(0.8, w * 0.75))
    p.curve(to: a, controlPoint1: at(0.8, -w * 0.75), controlPoint2: at(0.25, -w))
    p.close()
    return p
}

/// The logo on a 1024 × 1024 canvas, with the tile at `tileRect`. A shadow
/// does not follow the scale of the canvas, so `k` (pixels for one unit of
/// the canvas) scales it.
func drawLogo(_ shape: Shape, _ k: CGFloat) {
    let top: UInt32 = 0x4A7A57, bottom: UInt32 = 0x24402D
    let gradient = NSGradient(starting: hex(top), ending: hex(bottom))!
    if shape == .square {
        gradient.draw(in: tileRect, angle: -90)
        NSBezierPath(rect: tileRect).addClip()
    } else {
        let squircle = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)
        if shape == .mac {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 28 * k
            shadow.shadowOffset = NSSize(width: 0, height: -12 * k)
            shadow.set()
            hex(bottom).setFill()
            squircle.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        gradient.draw(in: squircle, angle: -90)
        squircle.addClip()
    }

    // the ground
    hex(0x1B3323, 0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: 182, y: -30, width: 660, height: 300)).fill()

    // stem
    let stem = NSBezierPath()
    stem.lineWidth = 34
    stem.lineCapStyle = .round
    stem.move(to: pt(512, 262))
    stem.curve(to: pt(512, 560), controlPoint1: pt(500, 360), controlPoint2: pt(530, 460))
    hex(0xF6F1E6).setStroke()
    stem.stroke()

    // left leaf, then the right leaf
    hex(0xF6F1E6).setFill()
    leaf(pt(512, 452), pt(262, 640), 104).fill()
    hex(0xDCE8CF).setFill()
    leaf(pt(514, 548), pt(778, 762), 118).fill()

    // a small sun, top left
    hex(0xD9B44A, 0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: 266, y: 766, width: 68, height: 68)).fill()
}

/// The logo at `px` pixels. Each size is drawn from the shapes, not scaled
/// down from a large picture.
func icon(_ px: Int, _ shape: Shape) -> NSBitmapImageRep {
    let alpha = shape != .square
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: alpha ? 4 : 3, hasAlpha: alpha, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: px * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(px) / S)
    if shape != .mac {
        // The tile fills the picture.
        scale.scale(by: S / tileRect.width)
        scale.translateX(by: -tileRect.minX, yBy: -tileRect.minY)
    }
    scale.concat()
    drawLogo(shape, CGFloat(px) / S)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

func write(_ data: Data, _ path: String) throws {
    try data.write(to: URL(fileURLWithPath: "\(root)/\(path)"))
}

// macOS
for px in [16, 32, 64, 128, 256, 512, 1024] {
    try write(png(icon(px, .mac)),
              "app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(px).png")
}

// iOS: the name gives the size in points and the scale.
let iosSizes: [(String, Double, [Int])] = [
    ("20x20", 20, [1, 2, 3]), ("29x29", 29, [1, 2, 3]), ("40x40", 40, [1, 2, 3]),
    ("60x60", 60, [2, 3]), ("76x76", 76, [1, 2]), ("83.5x83.5", 83.5, [2]), ("1024x1024", 1024, [1]),
]
for (name, points, scales) in iosSizes {
    for scale in scales {
        try write(png(icon(Int((points * Double(scale)).rounded()), .square)),
                  "app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-\(name)@\(scale)x.png")
    }
}

// Android
for (density, px) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
    try write(png(icon(px, .rounded)), "app/android/app/src/main/res/mipmap-\(density)/ic_launcher.png")
}

// Windows: one .ico file. The small sizes are bitmaps, 256 is a PNG.
func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }

/// A 32-bit bitmap as an .ico file holds it: rows from the bottom up, each
/// pixel blue, green, red, alpha (not multiplied), then an empty 1-bit mask.
func bitmap(_ rep: NSBitmapImageRep) -> [UInt8] {
    let px = rep.pixelsWide
    var out = le32(40) + le32(px) + le32(px * 2) + le16(1) + le16(32) + le32(0)
        + le32(px * px * 4) + le32(0) + le32(0) + le32(0) + le32(0)
    let data = rep.bitmapData!
    for row in stride(from: px - 1, through: 0, by: -1) {
        for column in 0..<px {
            let p = data + row * rep.bytesPerRow + column * 4
            let a = Int(p[3])
            func straight(_ c: UInt8) -> UInt8 { a == 0 ? 0 : UInt8(min(255, (Int(c) * 255 + a / 2) / a)) }
            out += [straight(p[2]), straight(p[1]), straight(p[0]), UInt8(a)]
        }
    }
    out += [UInt8](repeating: 0, count: ((px + 31) / 32) * 4 * px)
    return out
}

let icoSizes = [16, 24, 32, 48, 64, 256]
let images: [[UInt8]] = icoSizes.map { px in
    let rep = icon(px, .rounded)
    return px == 256 ? [UInt8](png(rep)) : bitmap(rep)
}
var ico = le16(0) + le16(1) + le16(icoSizes.count)
var offset = 6 + 16 * icoSizes.count
for (px, image) in zip(icoSizes, images) {
    ico += [UInt8(px == 256 ? 0 : px), UInt8(px == 256 ? 0 : px), 0, 0] + le16(1) + le16(32)
        + le32(image.count) + le32(offset)
    offset += image.count
}
for image in images { ico += image }
try write(Data(ico), "app/windows/runner/resources/app_icon.ico")

print("wrote the icons of macOS (7), iOS (15), Android (5) and Windows (1 file, \(icoSizes.count) sizes)")
