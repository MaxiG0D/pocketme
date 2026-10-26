import Foundation
import ImageIO
import LinkPresentation
import UniformTypeIdentifiers

actor ThumbnailService {
    func thumbnail(from url: URL) async throws -> Data {
        let (data, mime) = try await NetworkData.fetch(url, limit: 8 * 1_024 * 1_024)
        guard mime?.hasPrefix("image/") == true else { throw NetworkData.DownloadError.badResponse }
        return try downsample(data)
    }

    func downsample(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, width >= 120,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, height >= 80,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw NetworkData.DownloadError.badResponse }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { throw NetworkData.DownloadError.badResponse }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NetworkData.DownloadError.badResponse }
        return result as Data
    }
}

/// Apple’s page preview can find images that aren’t exposed in readable article HTML.
@MainActor
final class ThumbnailMetadata {
    func image(for url: URL) async -> Data? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        defer { provider.cancel() }
        return await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, _ in
                guard let image = metadata?.imageProvider else { continuation.resume(returning: nil); return }
                image.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data.flatMap { $0.count <= 8 * 1_024 * 1_024 ? $0 : nil })
                }
            }
        }
    }
}
