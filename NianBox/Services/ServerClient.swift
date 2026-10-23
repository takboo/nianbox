import Foundation

/// Reject redirects so a proxy cannot forward the bearer token to another origin.
private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class ServerClient: SyncTransport {
    let endpoint: String
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    static func validatedURL(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host)) else {
            throw SyncFailure.message("Use an HTTPS server origin (HTTP is allowed only on loopback).")
        }
        return url
    }

    init(url: String, token: String) throws {
        baseURL = try Self.validatedURL(url)
        guard token.count >= 32, token.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }) else {
            throw SyncFailure.message("Enter the server API token (at least 32 characters).")
        }
        self.token = token
        endpoint = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }

    func changes(after: Int64, digest: String? = nil) async throws -> ChangePage {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/changes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "after", value: String(after)), URLQueryItem(name: "limit", value: "200")]
        if let digest { components.queryItems?.append(URLQueryItem(name: "cursor_digest", value: digest)) }
        return try await send(URLRequest(url: components.url!))
    }

    func mutate(_ request: MutationRequest) async throws -> WireTask {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/mutations"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let reply: MutationReply = try await send(urlRequest)
        return reply.task
    }

    private func send<T: Decodable>(_ input: URLRequest) async throws -> T {
        var request = input
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncFailure.message("Invalid server response") }
        guard (200..<300).contains(http.statusCode) else {
            if let rejection = try? WireDate.decoder.decode(ServerRejection.self, from: data) { throw rejection }
            throw SyncFailure.message("Server returned HTTP \(http.statusCode). Local changes are retained.")
        }
        return try WireDate.decoder.decode(T.self, from: data)
    }
}
