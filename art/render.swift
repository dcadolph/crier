// render.swift cuts the bell out of art/source.png and renders the app icon, the menu bar glyph, the
// bell cutout, and the README banner. Run it from the repo root with `swift art/render.swift`.

import AppKit
import CoreGraphics

// RGBA is one 8-bit pixel buffer with its size.
struct RGBA {
    // width is the buffer width in pixels.
    let width: Int
    // height is the buffer height in pixels.
    let height: Int
    // pixels holds four bytes per pixel, row by row, top row first.
    var pixels: [UInt8]

    // init draws an image into a new buffer.
    init(_ image: CGImage) {
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // init builds an empty buffer.
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    // image wraps the buffer as a premultiplied image.
    func image() -> CGImage {
        var copy = pixels
        return copy.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!.makeImage()!
        }
    }
}

// load reads a PNG from disk.
func load(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("cannot read \(path)")
    }
    return image
}

// save writes an image to disk as PNG.
func save(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode \(path)")
    }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(image.width)x\(image.height)")
}

// canvas returns a transparent sRGB drawing context.
func canvas(_ width: Int, _ height: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    return context
}

// squircle returns the macOS icon tile outline, a superellipse that matches Apple's continuous corners.
func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 720
    for step in 0...steps {
        let t = Double(step) / Double(steps) * 2 * .pi
        let c = cos(t)
        let s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

let source = RGBA(load("art/source.png"))

// The tile is every dark pixel. Its median color becomes the ink, and its box bounds the bell search.
var darks: [(Int, Int, Int)] = []
var tileMin = (x: source.width, y: source.height)
var tileMax = (x: 0, y: 0)
for y in 0..<source.height {
    for x in 0..<source.width {
        let i = (y * source.width + x) * 4
        let r = Int(source.pixels[i])
        let g = Int(source.pixels[i + 1])
        let b = Int(source.pixels[i + 2])
        if max(r, g, b) < 60 {
            darks.append((r, g, b))
            tileMin = (min(tileMin.x, x), min(tileMin.y, y))
            tileMax = (max(tileMax.x, x), max(tileMax.y, y))
        }
    }
}
func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
let ink = (median(darks.map { $0.0 }), median(darks.map { $0.1 }), median(darks.map { $0.2 }))
print("tile \(tileMin) to \(tileMax), ink \(ink)")

// The bell is every light or red pixel well inside the tile, with alpha from its distance to the ink so
// the edges stay smooth.
let inset = (tileMax.x - tileMin.x) / 8
var bell = RGBA(width: source.width, height: source.height)
var bellMin = (x: source.width, y: source.height)
var bellMax = (x: 0, y: 0)
for y in (tileMin.y + inset)..<(tileMax.y - inset) {
    for x in (tileMin.x + inset)..<(tileMax.x - inset) {
        let i = (y * source.width + x) * 4
        let channels = (0..<3).map { Double(source.pixels[i + $0]) }
        let inks = [Double(ink.0), Double(ink.1), Double(ink.2)]
        let lift = channels.max()! - inks.max()!
        let alpha = min(1, max(0, (lift - 20) / 150))
        guard alpha > 0 else { continue }
        for c in 0..<3 {
            let straight = (channels[c] - (1 - alpha) * inks[c]) / alpha
            bell.pixels[i + c] = UInt8(min(255, max(0, straight * alpha)))
        }
        bell.pixels[i + 3] = UInt8(alpha * 255)
        if alpha > 0.5 {
            bellMin = (min(bellMin.x, x), min(bellMin.y, y))
            bellMax = (max(bellMax.x, x), max(bellMax.y, y))
        }
    }
}
let pad = 6
let cropRect = CGRect(
    x: bellMin.x - pad, y: bellMin.y - pad, width: bellMax.x - bellMin.x + 2 * pad,
    height: bellMax.y - bellMin.y + 2 * pad
)
let cutout = bell.image().cropping(to: cropRect)!
save(cutout, "art/bell.png")

let inkColor = CGColor(
    srgbRed: CGFloat(ink.0) / 255, green: CGFloat(ink.1) / 255, blue: CGFloat(ink.2) / 255, alpha: 1
)

// draw places the bell centered in a box so its larger side fills the given share of the box.
func draw(_ image: CGImage, in context: CGContext, box: CGRect, share: CGFloat) {
    let scale = min(box.width, box.height) * share / CGFloat(max(image.width, image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let origin = CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
    context.draw(image, in: CGRect(origin: origin, size: size))
}

// App icon on Apple's 1024 grid: an 824 point tile with a soft drop shadow.
let icon = canvas(1024, 1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
icon.saveGState()
icon.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
icon.addPath(squircle(tile))
icon.setFillColor(inkColor)
icon.fillPath()
icon.restoreGState()
draw(cutout, in: icon, box: tile, share: 0.66)
save(icon.makeImage()!, "art/app-icon.png")

// Menu bar glyph: the bell shape alone in black, for a template image macOS tints itself.
for (size, name) in [(18, "art/glyph.png"), (36, "art/glyph@2x.png")] {
    let glyph = canvas(size, size)
    let box = CGRect(x: 0, y: 0, width: size, height: size)
    draw(cutout, in: glyph, box: box, share: 0.98)
    glyph.setBlendMode(.sourceIn)
    glyph.setFillColor(CGColor(gray: 0, alpha: 1))
    glyph.fill(box)
    save(glyph.makeImage()!, name)
}

// README banner: the bell centered on a solid ink band, about 3 to 1, no text.
let banner = canvas(3000, 1000)
banner.setFillColor(inkColor)
banner.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
draw(cutout, in: banner, box: CGRect(x: 0, y: 0, width: 3000, height: 1000), share: 0.7)
save(banner.makeImage()!, "art/banner.png")
