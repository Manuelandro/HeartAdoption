import Foundation
import Security

struct APIClient {
    let baseURL: URL
    var token: String?

    func request<T: Decodable>(_ method: String = "GET", _ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send(method, path, body: body, query: query)
        return try AppJSON.decoder().decode(T.self, from: data)
    }

    func send(_ method: String, _ path: String, body: (any Encodable)? = nil, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 30
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try AppJSON.encoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppFailure.message("The server did not send a response.") }
        guard (200..<300).contains(response.statusCode) else {
            struct ServerError: Decodable { let message: String }
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).message) ?? "The request failed. Please try again."
            throw AppFailure.server(status: response.statusCode, message: message)
        }
        return data
    }

    static func validatedURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw AppFailure.message("Enter an HTTPS server address. For the simulator, you can use http://localhost:8787.")
        }
        return url
    }
}

enum SessionKeychain {
    private static let service = "com.heartadoption.session"
    static func save(_ token: String, server: URL) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: server.absoluteString]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppFailure.message("Your session could not be saved securely. Please sign in again.") }
    }
    static func read(server: URL) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: server.absoluteString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func remove(server: URL) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: server.absoluteString] as CFDictionary)
    }
}
