import AppKit

// Renders SwiftStar's AppIcon (a white star on a rounded indigo tile) at all
// iconset sizes and writes the iconset directory passed as argv[1].
// Usage: swift Tools/make-icon.swift <iconset-dir>

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.systemIndigo.setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()
    let star = NSBezierPath()
    let center = NSPoint(x: size / 2, y: size / 2)
    let radius = Double(size) * 0.34
    for i in 0..<10 {
        let angle = Double.pi / 2 + Double(i) * Double.pi / 5
        let r = (i % 2 == 0) ? radius : radius * 0.45
        let p = NSPoint(x: center.x + CGFloat(cos(angle) * r), y: center.y + CGFloat(sin(angle) * r))
        if i == 0 { star.move(to: p) } else { star.line(to: p) }
    }
    star.close()
    NSColor.white.setFill()
    star.fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let filename = size <= 512
        ? "icon_\(size)x\(size).png"
        : "icon_512x512@2x.png"
    try png.write(to: iconset.appendingPathComponent(filename))
}
