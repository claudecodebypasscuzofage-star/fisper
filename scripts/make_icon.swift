// Renders Fisper's app icon (1024px) — run: swift scripts/make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS squircle-ish rounded rect with margin (Big Sur+ icon grid: 824px body)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
ctx.saveGState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(srgbRed: 0.05, green: 0.35, blue: 0.31, alpha: 1).setFill(); path.fill()
ctx.restoreGState()

path.addClip()
let grad = NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.47, blue: 0.41, alpha: 1), NSColor(srgbRed: 0.03, green: 0.27, blue: 0.24, alpha: 1)])!
grad.draw(in: body, angle: -90)
// soft top highlight
let hl = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
hl.draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)

// cream capsule (the "flow bar")
let pill = NSRect(x: 232, y: 392, width: 560, height: 240)
let pillPath = NSBezierPath(roundedRect: pill, xRadius: 120, yRadius: 120)
NSColor(srgbRed: 1.0, green: 0.996, blue: 0.91, alpha: 1).setFill(); pillPath.fill()

// waveform bars
let heights: [CGFloat] = [0.32, 0.6, 0.92, 0.55, 0.78, 0.4, 0.22]
let barW: CGFloat = 30, gap: CGFloat = 26
let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = pill.midX - total / 2
for h in heights {
    let bh = (pill.height - 70) * h
    let r = NSRect(x: x, y: pill.midY - bh / 2, width: barW, height: bh)
    NSColor(srgbRed: 0.05, green: 0.30, blue: 0.27, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
    x += barW + gap
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
