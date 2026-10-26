import Foundation

enum NetworkData {
    enum DownloadError: Error { case badResponse, tooLarge, invalidURL }
    static func fetch(_ url: URL, limit: Int) async throws -> (Data, String?) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw DownloadError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw DownloadError.badResponse }
        guard response.expectedContentLength <= limit else { throw DownloadError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw DownloadError.tooLarge }
            data.append(byte)
        }
        return (data, response.mimeType)
    }
}
