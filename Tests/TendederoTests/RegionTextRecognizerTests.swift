#if !STANDALONE_TESTS
import AppKit
import XCTest
@testable import Tendedero

final class RegionTextRecognizerTests: XCTestCase {
    /// A white 800x200 bitmap, optionally with black system-font text drawn on it.
    private func image(text: String?) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 200))
        if let text {
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            (text as NSString).draw(at: CGPoint(x: 30, y: 70),
                withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testRecognizesRenderedText() throws {
        let result = try RegionTextRecognizer.text(in: try image(text: "Hello Copyline 123"))
        XCTAssertTrue(result.contains("Hello"), result)
        XCTAssertTrue(result.contains("123"), result)
    }

    func testBlankImageGivesEmptyString() throws {
        XCTAssertEqual(try RegionTextRecognizer.text(in: try image(text: nil)), "")
    }
}
#endif
