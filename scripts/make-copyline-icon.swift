// Copyline's own icon: three stacked image cards leaning on the right edge.
// Original artwork; it uses neither Tendedero's nor ClipBoardLine's icon.
// Usage: make-copyline-icon <output.png>   (1024 x 1024)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Background tile with a vertical gradient.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.saveGState()
context.addPath(rounded(tile, 185))
context.clip()
let background = CGGradient(colorsSpace: space, colors: [color(0.36, 0.42, 0.98), color(0.16, 0.18, 0.55)] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
context.restoreGState()

// Three cards, newest on top, set towards the right edge.
let cards: [(rect: CGRect, top: CGColor, bottom: CGColor)] = [
    (CGRect(x: 430, y: 210, width: 360, height: 180), color(1, 1, 1, 0.38), color(1, 1, 1, 0.26)),
    (CGRect(x: 380, y: 410, width: 410, height: 180), color(1, 1, 1, 0.66), color(1, 1, 1, 0.52)),
    (CGRect(x: 320, y: 610, width: 470, height: 200), color(1, 1, 1, 1), color(0.90, 0.93, 1, 1))
]
for card in cards {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0.05, 0.06, 0.25, 0.35))
    context.addPath(rounded(card.rect, 44))
    context.setFillColor(card.top)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(rounded(card.rect, 44))
    context.clip()
    let fill = CGGradient(colorsSpace: space, colors: [card.top, card.bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: card.rect.maxY), end: CGPoint(x: 0, y: card.rect.minY), options: [])
    context.restoreGState()
}

// A small picture mark on the top card: a sun and a hill.
let top = cards[2].rect
context.saveGState()
context.addPath(rounded(top.insetBy(dx: 26, dy: 26), 24))
context.clip()
context.setFillColor(color(0.80, 0.86, 1))
context.fill(top)
context.setFillColor(color(1, 0.78, 0.30))
context.fillEllipse(in: CGRect(x: top.minX + 70, y: top.maxY - 110, width: 54, height: 54))
context.setFillColor(color(0.30, 0.36, 0.92))
context.move(to: CGPoint(x: top.minX + 26, y: top.minY + 26))
context.addLine(to: CGPoint(x: top.minX + 190, y: top.minY + 120))
context.addLine(to: CGPoint(x: top.minX + 270, y: top.minY + 76))
context.addLine(to: CGPoint(x: top.maxX - 26, y: top.minY + 150))
context.addLine(to: CGPoint(x: top.maxX - 26, y: top.minY + 26))
context.closePath()
context.fillPath()
context.restoreGState()

guard CommandLine.arguments.count == 2, let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
          UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("usage: make-copyline-icon <output.png>\n".data(using: .utf8)!)
    exit(2)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
