// Draws the AWDL Guard app icon and writes Resources/AppIcon.icns.
//
//   swift packaging/icon/make-icon.swift      (or: make icon)
//
// Drawn on a 160-unit design grid (the squircle spans 4...156), scaled into Apple's
// 1024 px macOS icon template (824 px squircle, 100 px margin).
import AppKit

let green = CGColor(srgbRed: 0.169, green: 0.831, blue: 0.478, alpha: 1)

/// `pixels` is the output size; shadows are not scaled by the CTM, so they use it directly.
func drawIcon(_ ctx: CGContext, pixels: CGFloat) {
    let px = pixels / 1024
    // Top-left origin, design units.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: 100, y: 100)
    ctx.scaleBy(x: 824 / 152, y: 824 / 152)
    ctx.translateBy(x: -4, y: -4)

    let tile = CGRect(x: 4, y: 4, width: 152, height: 152)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 34.2, cornerHeight: 34.2, transform: nil)

    // Drop shadow as in Apple's template.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * px), blur: 28 * px, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(CGColor(gray: 0.07, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: a slightly lighter centre.
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [CGColor(gray: 0.12, alpha: 1), CGColor(gray: 0.055, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: 80, y: 80), startRadius: 0,
                           endCenter: CGPoint(x: 80, y: 80), endRadius: 110, options: [.drawsAfterEndLocation])

    // Waves, fading with distance.
    let center = CGPoint(x: 80, y: 80)
    let waves: [(radius: CGFloat, width: CGFloat, alpha: CGFloat)] = [
        (22, 4.4, 1), (34, 4, 0.75), (46, 3.6, 0.45), (58, 3, 0.22),
    ]
    ctx.setLineCap(.round)
    for w in waves {
        ctx.setStrokeColor(green.copy(alpha: w.alpha)!)
        ctx.setLineWidth(w.width)
        for mid in [CGFloat.pi, 0] {
            ctx.addArc(center: center, radius: w.radius, startAngle: mid - .pi / 4, endAngle: mid + .pi / 4,
                       clockwise: false)
            ctx.strokePath()
        }
    }

    // Shield with a soft glow. A shield is top-heavy, so it sits 1.5 units low to look centred
    // between the waves; the dot stays at the waves' centre, which is the shield's visual centre.
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 80, y: 65))
    shield.addLine(to: CGPoint(x: 92, y: 69.5))
    shield.addLine(to: CGPoint(x: 92, y: 80))
    shield.addCurve(to: CGPoint(x: 80, y: 96), control1: CGPoint(x: 92, y: 87.5), control2: CGPoint(x: 87, y: 92.5))
    shield.addCurve(to: CGPoint(x: 68, y: 80), control1: CGPoint(x: 73, y: 92.5), control2: CGPoint(x: 68, y: 87.5))
    shield.addLine(to: CGPoint(x: 68, y: 69.5))
    shield.closeSubpath()
    ctx.saveGState()
    ctx.translateBy(x: 0, y: 1.5)
    ctx.setShadow(offset: .zero, blur: 60 * px, color: green.copy(alpha: 0.6))
    ctx.addPath(shield)
    ctx.setFillColor(green)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 76.5, y: 76.5, width: 7, height: 7))
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(ctx, pixels: CGFloat(size))
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(size: 1024).write(to: root.appendingPathComponent("docs/icon.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(out.path)")
