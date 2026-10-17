import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
    let outline = NSBezierPath(roundedRect: rect, xRadius: 194, yRadius: 194)
    NSGradient(starting: NSColor(calibratedRed: 0.25, green: 0.33, blue: 0.40, alpha: 1), ending: NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.22, alpha: 1))!.draw(in: outline, angle: -90)
    NSColor.white.withAlphaComponent(0.2).setStroke()
    outline.lineWidth = 2
    outline.stroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 245, y: 505))
    path.line(to: NSPoint(x: 350, y: 505))
    path.curve(to: NSPoint(x: 400, y: 590), controlPoint1: NSPoint(x: 375, y: 505), controlPoint2: NSPoint(x: 383, y: 590))
    path.curve(to: NSPoint(x: 473, y: 330), controlPoint1: NSPoint(x: 423, y: 590), controlPoint2: NSPoint(x: 445, y: 330))
    path.curve(to: NSPoint(x: 560, y: 697), controlPoint1: NSPoint(x: 500, y: 330), controlPoint2: NSPoint(x: 533, y: 697))
    path.curve(to: NSPoint(x: 637, y: 505), controlPoint1: NSPoint(x: 588, y: 697), controlPoint2: NSPoint(x: 605, y: 505))
    path.line(to: NSPoint(x: 779, y: 505))
    NSColor(calibratedRed: 0.86, green: 0.96, blue: 0.96, alpha: 1).setStroke()
    path.lineWidth = 39
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
}
