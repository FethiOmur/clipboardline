// The app icon: the luminous letter from scripts/app-logo.png (generated
// artwork on pure black) set on a black macOS-style rounded tile.
// It uses neither Tendedero's nor ClipBoardLine's icon.
// Usage: make-app-icon <logo.png> <output.png>   (output is 1024 x 1024)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("usage: make-app-icon <logo.png> <output.png>\n".data(using: .utf8)!)
    exit(2)
}

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high

// The standard macOS icon tile: 824 pt inside a 1024 pt canvas, with a
// transparent margin around it.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
context.clip()
context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(tile)
// The logo's own black background meets the tile's, so only the letter and
// its glow show.
context.draw(logo, in: tile)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL,
          UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
