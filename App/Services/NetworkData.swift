import Foundation

enum NetworkData {
    enum DownloadError: Error { case badResponse, tooLarge, invalidURL }
    static func fetch(_ url: URL, limit: Int) async throws -> (Data, String?) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw DownloadError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw DownloadError.badResponse }
        guard data.count <= limit else { throw DownloadError.tooLarge }
        return (data, response.mimeType)
    }
}
