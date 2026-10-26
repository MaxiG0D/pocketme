import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PocketMe

struct ThumbnailTests {
    @Test func downsamplesLargeImagesAndRejectsTrackingPixels() async throws {
        let service = ThumbnailService()
        let large = try image(width: 1200, height: 800)
        let thumbnail = try await service.downsample(large)
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 600)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 400)
        let pixel = try image(width: 1, height: 1)
        await #expect(throws: NetworkData.DownloadError.self) { try await service.downsample(pixel) }
    }

    private func image(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
