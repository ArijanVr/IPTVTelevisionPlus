import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ARJOUI

final class ImageLoaderTests: XCTestCase {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testDownsampleKeepsAspectRatioAndLimitsTheLongSide() throws {
        let image = try XCTUnwrap(ImageLoader.downsample(try pngData(width: 1_000, height: 500), maxPixel: 200))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
    }

    func testSmallImagesAreNotUpscaledBeyondTheTarget() throws {
        let image = try XCTUnwrap(ImageLoader.downsample(try pngData(width: 50, height: 40), maxPixel: 200))
        XCTAssertLessThanOrEqual(max(image.width, image.height), 200)
    }

    func testGarbageDataGivesNoImage() {
        XCTAssertNil(ImageLoader.downsample(Data("kein Bild".utf8), maxPixel: 200))
    }
}
