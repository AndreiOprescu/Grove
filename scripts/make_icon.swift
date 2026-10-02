import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let S = 1024

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

// soft drop shadow
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
hex(0xF0E9D6).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

// paper gradient
NSGradient(starting: hex(0xF6F1E6), ending: hex(0xE9E0CB))!.draw(in: squircle, angle: -90)
squircle.addClip()

// warm sun dot, top right
hex(0xD9B44A, 0.30).setFill()
NSBezierPath(ovalIn: NSRect(x: 650, y: 650, width: 190, height: 190)).fill()

// stem
let stem = NSBezierPath()
stem.lineWidth = 26
stem.lineCapStyle = .round
stem.move(to: NSPoint(x: 512, y: 230))
stem.curve(to: NSPoint(x: 540, y: 560), controlPoint1: NSPoint(x: 500, y: 360), controlPoint2: NSPoint(x: 560, y: 450))
hex(0x5E7F4F).setStroke()
stem.stroke()

// left leaf
let left = NSBezierPath()
left.move(to: NSPoint(x: 520, y: 400))
left.curve(to: NSPoint(x: 250, y: 560), controlPoint1: NSPoint(x: 420, y: 400), controlPoint2: NSPoint(x: 290, y: 430))
left.curve(to: NSPoint(x: 520, y: 400), controlPoint1: NSPoint(x: 340, y: 640), controlPoint2: NSPoint(x: 480, y: 560))
hex(0xA9C79A).setFill()
left.fill()

// right leaf (its outline reads as a check mark)
let right = NSBezierPath()
right.move(to: NSPoint(x: 540, y: 470))
right.curve(to: NSPoint(x: 800, y: 690), controlPoint1: NSPoint(x: 660, y: 470), controlPoint2: NSPoint(x: 780, y: 560))
right.curve(to: NSPoint(x: 540, y: 470), controlPoint1: NSPoint(x: 700, y: 760), controlPoint2: NSPoint(x: 560, y: 650))
hex(0x7FA36B).setFill()
right.fill()

let check = NSBezierPath()
check.lineWidth = 22
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.move(to: NSPoint(x: 590, y: 540))
check.line(to: NSPoint(x: 650, y: 500))
check.line(to: NSPoint(x: 760, y: 665))
hex(0xF6F1E6).setStroke()
check.stroke()

NSGraphicsContext.restoreGraphicsState()
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: outDir + "/AppIcon-1024.png"))
print("wrote \(outDir)/AppIcon-1024.png (\(rep.pixelsWide)x\(rep.pixelsHigh))")
