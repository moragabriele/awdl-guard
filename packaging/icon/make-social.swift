// Draws the GitHub social preview (1280×640) from docs/icon.png and writes
// docs/social-preview.png. Upload it in the repository's Settings > Social preview.
//
//   swift packaging/icon/make-social.swift      (or: make social)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardized
let width: CGFloat = 1280, height: CGFloat = 640

let green = NSColor(srgbRed: 0.169, green: 0.831, blue: 0.478, alpha: 1)
let red = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.36, alpha: 1)
let light = NSColor(srgbRed: 0.70, green: 0.76, blue: 0.73, alpha: 1)
let dim = NSColor(srgbRed: 0.46, green: 0.52, blue: 0.49, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background with a soft green glow behind the chart's calm half.
NSColor(srgbRed: 0.043, green: 0.067, blue: 0.055, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let glow = CGGradient(colorsSpace: nil, colors: [green.withAlphaComponent(0.16).cgColor,
                                                 green.withAlphaComponent(0).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 960, y: 140), startRadius: 0,
                       endCenter: CGPoint(x: 960, y: 140), endRadius: 520, options: [])

/// Draws `text` with its baseline at `y`, measured from the top; returns its width.
@discardableResult
func text(_ parts: [(String, NSColor)], x: CGFloat, y: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, mono: Bool = false) -> CGFloat {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let string = NSMutableAttributedString()
    for (part, color) in parts {
        string.append(NSAttributedString(string: part, attributes: [.font: font, .foregroundColor: color, .kern: size * -0.02]))
    }
    string.draw(at: NSPoint(x: x, y: height - y + font.descender))
    return string.size().width
}

// Header: icon and name.
let icon = NSImage(contentsOf: root.appendingPathComponent("docs/icon.png"))!
icon.draw(in: NSRect(x: 52, y: height - 132, width: 96, height: 96))
text([("AWDL Guard", .white)], x: 150, y: 96, size: 36, weight: .semibold)
text([("github.com/moragabriele/awdl-guard", dim)], x: 820, y: 94, size: 20, mono: true)

// Headline.
text([("Kill the ", .white), ("Wi-Fi lag.", green)], x: 64, y: 268, size: 112, weight: .heavy)
text([("Holds AirDrop's radio down during calls and games. Any Mac, any MDM.", light)],
     x: 66, y: 330, size: 30)

// Ping chart: spiky with AWDL on, flat with AWDL Guard. Illustrative shape, fixed seed.
let base: CGFloat = 560, mid: CGFloat = 640
var seed: UInt64 = 7
func random() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat(seed >> 33) / CGFloat(1 << 31)
}

func line(from x0: CGFloat, to x1: CGFloat, color: NSColor, height h: (CGFloat) -> CGFloat) {
    let path = CGMutablePath()
    var x = x0
    path.move(to: CGPoint(x: x, y: height - base))
    while x <= x1 {
        path.addLine(to: CGPoint(x: x, y: height - base + h(x)))
        x += 6
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 14, color: color.withAlphaComponent(0.7).cgColor)
    ctx.addPath(path)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(3.5)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

line(from: 64, to: mid - 40, color: red) { _ in
    let r = random()
    return r > 0.86 ? 40 + random() * 110 : r > 0.6 ? 10 + random() * 30 : random() * 8
}
line(from: mid + 40, to: 1216, color: green) { _ in random() * 5 }

// Divider between the halves.
ctx.setStrokeColor(dim.withAlphaComponent(0.5).cgColor)
ctx.setLineWidth(2)
ctx.setLineDash(phase: 0, lengths: [6, 8])
ctx.move(to: CGPoint(x: mid, y: height - base - 30))
ctx.addLine(to: CGPoint(x: mid, y: height - base + 160))
ctx.strokePath()

text([("AWDL on: 84–143 lag spikes / min", red)], x: 64, y: 604, size: 24, weight: .medium)
text([("AWDL Guard: 0", green)], x: mid + 40, y: 604, size: 24, weight: .semibold)

let out = root.appendingPathComponent("docs/social-preview.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
