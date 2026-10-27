#if os(macOS)
import Foundation
import Network

/// Lets the Chrome extension hand links to the running app. It only listens on this Mac's loopback address
/// and only accepts requests that come from a Chrome extension.
final class LocalSaveServer: @unchecked Sendable {
    static let port: NWEndpoint.Port = 47321
    private let queue = DispatchQueue(label: "pocketme.local-save")
    private var listener: NWListener?

    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: Self.port)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffered: Data())
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffered
            if let data { buffer.append(data) }
            if let request = Request(buffer) {
                self.handle(request, on: connection)
            } else if isComplete || error != nil || buffer.count > 65_536 {
                connection.cancel()
            } else {
                self.receive(connection, buffered: buffer)
            }
        }
    }

    private func handle(_ request: Request, on connection: NWConnection) {
        guard let origin = request.headers["origin"], origin.hasPrefix("chrome-extension://") else {
            return respond(connection, status: "403 Forbidden", origin: nil, body: #"{"saved":false}"#)
        }
        if request.method == "OPTIONS" { return respond(connection, status: "204 No Content", origin: origin, body: "") }
        guard request.method == "POST", request.path == "/save", request.headers["x-pocketme"] == "1",
              let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let url = json["url"] as? String else {
            return respond(connection, status: "400 Bad Request", origin: origin, body: #"{"saved":false}"#)
        }
        let title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        Task {
            var saved = false
            if let saveQueue = try? SaveQueue(directory: AppIdentity.inboxURL) {
                saved = (try? await saveQueue.append(url: url, title: title)) != nil
            }
            self.respond(connection, status: "200 OK", origin: origin, body: saved ? #"{"saved":true}"# : #"{"saved":false}"#)
        }
    }

    private func respond(_ connection: NWConnection, status: String, origin: String?, body: String) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n"
        if let origin {
            head += "Access-Control-Allow-Origin: \(origin)\r\nAccess-Control-Allow-Headers: content-type, x-pocketme\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Private-Network: true\r\n"
        }
        connection.send(content: Data((head + "\r\n" + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        init?(_ data: Data) {
            guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return nil }
            var lines = head.components(separatedBy: "\r\n")
            let parts = lines.removeFirst().split(separator: " ")
            guard parts.count >= 2 else { return nil }
            method = String(parts[0]); path = String(parts[1])
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            self.headers = headers
            let length = Int(headers["content-length"] ?? "") ?? 0
            let body = data[separator.upperBound...]
            guard body.count >= length else { return nil }
            self.body = Data(body.prefix(length))
        }
    }
}
#endif
