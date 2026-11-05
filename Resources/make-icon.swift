// Renders the TouchCursor app icon (1024×1024 PNG) with CoreGraphics.
// Blueprint-style close-up of a keyboard: I/J/K/L shown as solid arrow keys,
// with a solid spacebar (the modifier) below.
//
// Usage: swift Resources/make-icon.swift <output.png>

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let blue = rgb(0x1E40AF)
let white = rgb(0xFFFFFF)

let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin so layout numbers read naturally.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

enum Dir {
    case up, down, left, right
    var vector: (CGFloat, CGFloat) {
        switch self {
        case .up: (0, -1)
        case .down: (0, 1)
        case .left: (-1, 0)
        case .right: (1, 0)
        }
    }
}

func arrow(_ dir: Dir, at c: CGPoint, color: CGColor) {
    let len: CGFloat = 38, head: CGFloat = 28
    let (dx, dy) = dir.vector
    let tip = CGPoint(x: c.x + dx * len, y: c.y + dy * len)
    let tail = CGPoint(x: c.x - dx * len, y: c.y - dy * len)
    let back = CGPoint(x: tip.x - dx * head, y: tip.y - dy * head)
    let px = -dy, py = dx
    ctx.saveGState()
    ctx.setStrokeColor(color); ctx.setLineWidth(18); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: tail); ctx.addLine(to: tip)
    ctx.move(to: CGPoint(x: back.x + px * head, y: back.y + py * head))
    ctx.addLine(to: tip)
    ctx.addLine(to: CGPoint(x: back.x - px * head, y: back.y - py * head))
    ctx.strokePath()
    ctx.restoreGState()
}

func label(_ s: String, in r: CGRect) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let str = NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .light),
        .foregroundColor: NSColor(cgColor: rgb(0xFFFFFF, 0.55))!,
    ])
    let b = str.size()
    str.draw(at: CGPoint(x: r.midX - 30 - b.width / 2, y: r.midY - 30 - b.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Background: macOS icon grid (824pt body, 100pt inset) with blueprint grid

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = roundedRect(body, 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(blue); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(bodyPath); ctx.clip()

ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(2)
for i in stride(from: CGFloat(100), through: 924, by: 41.2) {
    ctx.move(to: CGPoint(x: i, y: 100)); ctx.addLine(to: CGPoint(x: i, y: 924))
    ctx.move(to: CGPoint(x: 100, y: i)); ctx.addLine(to: CGPoint(x: 924, y: i))
}
ctx.strokePath()

// MARK: Keyboard, tilted and cropped

ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -0.22); ctx.scaleBy(x: 1.08, y: 1.08); ctx.translateBy(x: -512, y: -512)

let k: CGFloat = 150, step: CGFloat = 168
let arrows: [Character: Dir] = ["I": .up, "J": .left, "K": .down, "L": .right]
let rows: [(keys: String, anchor: Int, offset: CGFloat, y: CGFloat)] = [
    ("4567890-=", 5, -60, -30),
    ("ERTYUIOP[", 5, 0, 138),
    ("DFGHJKL;'", 5, 40, 306),
    ("CVBNM,./", 4, -40, 474),
]

for row in rows {
    for (i, ch) in row.keys.enumerated() {
        let r = CGRect(x: 437 + CGFloat(i - row.anchor) * step + row.offset, y: row.y, width: k, height: k)
        if let dir = arrows[ch] {
            ctx.addPath(roundedRect(r, 26)); ctx.setFillColor(white); ctx.fillPath()
            arrow(dir, at: CGPoint(x: r.midX, y: r.midY), color: blue)
        } else {
            ctx.addPath(roundedRect(r.insetBy(dx: 2, dy: 2), 26))
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.55)); ctx.setLineWidth(5); ctx.strokePath()
            ctx.addPath(roundedRect(r.insetBy(dx: 22, dy: 22), 16))
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.2)); ctx.setLineWidth(3); ctx.strokePath()
            label(String(ch), in: r)
        }
    }
}

// Spacebar with ␣ glyph
let bar = CGRect(x: 190, y: 642, width: 640, height: 150)
ctx.addPath(roundedRect(bar, 26)); ctx.setFillColor(white); ctx.fillPath()
let gw: CGFloat = 120, gh: CGFloat = 30, gx = bar.midX - gw / 2, gy = bar.midY - gh / 2 + 4
ctx.setStrokeColor(blue); ctx.setLineWidth(16); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: gx, y: gy)); ctx.addLine(to: CGPoint(x: gx, y: gy + gh))
ctx.addLine(to: CGPoint(x: gx + gw, y: gy + gh)); ctx.addLine(to: CGPoint(x: gx + gw, y: gy))
ctx.strokePath()

// MARK: Write PNG

let image = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
