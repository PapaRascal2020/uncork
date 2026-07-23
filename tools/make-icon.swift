import AppKit
import Foundation

// Renders the Uncork app icon: a cream wine bottle (cork lifting off — "uncork")
// on a wine-red squircle, output as a full .iconset.

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Uncork.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let S = CGFloat(px)
    let img = NSImage(size: NSSize(width: S, height: S))
    img.lockFocus()

    // --- background squircle with a wine-red vertical gradient ---
    let inset = S * 0.05
    let bgRect = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: S*0.225, yRadius: S*0.225)
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [NSColor(red: 0.80, green: 0.18, blue: 0.26, alpha: 1),
                        NSColor(red: 0.28, green: 0.04, blue: 0.10, alpha: 1)])!
        .draw(in: bgRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // --- bottle silhouette (cream) ---
    let cx = S/2
    let bw = S*0.30, nw = S*0.115
    let bodyBottom = S*0.16, bodyTop = S*0.52, neckTop = S*0.74
    let cream = NSColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1)
    let b = NSBezierPath()
    b.move(to: NSPoint(x: cx-bw/2, y: bodyBottom+S*0.03))
    b.appendArc(withCenter: NSPoint(x: cx-bw/2+S*0.03, y: bodyBottom+S*0.03),
                radius: S*0.03, startAngle: 180, endAngle: 270)
    b.line(to: NSPoint(x: cx+bw/2-S*0.03, y: bodyBottom))
    b.appendArc(withCenter: NSPoint(x: cx+bw/2-S*0.03, y: bodyBottom+S*0.03),
                radius: S*0.03, startAngle: 270, endAngle: 360)
    b.line(to: NSPoint(x: cx+bw/2, y: bodyTop))
    b.curve(to: NSPoint(x: cx+nw/2, y: neckTop),
            controlPoint1: NSPoint(x: cx+bw/2, y: bodyTop+S*0.11),
            controlPoint2: NSPoint(x: cx+nw/2, y: bodyTop+S*0.05))
    b.line(to: NSPoint(x: cx-nw/2, y: neckTop))
    b.curve(to: NSPoint(x: cx-bw/2, y: bodyTop),
            controlPoint1: NSPoint(x: cx-nw/2, y: bodyTop+S*0.05),
            controlPoint2: NSPoint(x: cx-bw/2, y: bodyTop+S*0.11))
    b.close()
    cream.setFill(); b.fill()

    // --- wine-red label band on the body ---
    let label = NSBezierPath(rect: CGRect(x: cx-bw/2, y: S*0.26, width: bw, height: S*0.13))
    NSColor(red: 0.72, green: 0.16, blue: 0.24, alpha: 1).setFill(); label.fill()

    // --- cork lifted slightly off the neck (the "uncork") ---
    let cork = NSBezierPath(roundedRect: CGRect(x: cx-nw*0.7, y: neckTop+S*0.03,
                                                width: nw*1.4, height: S*0.075),
                            xRadius: S*0.02, yRadius: S*0.02)
    NSColor(red: 0.82, green: 0.60, blue: 0.34, alpha: 1).setFill(); cork.fill()

    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

// iconset needs these (name, pixel) pairs
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(variants.count) icons to \(out)")
