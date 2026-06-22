import Foundation

/// Talks to the hosted gateway (your Cloudflare Worker). Users sign in with an
/// email code (no API key), the gateway rate-limits + forwards to a free model.
struct HostedProvider: RewriteProvider {
    let baseURL: String
    let token: String

    func stream(text: String,
                systemPrompt: String,
                onDelta: @Sendable @escaping (String) -> Void) async throws -> String {
        guard !token.isEmpty else { throw RewriteError.signedOut }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/v1/rewrite") else {
            throw RewriteError.badResponse("Invalid gateway URL. Set it in Settings → Free models.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["systemPrompt": systemPrompt, "text": text])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw RewriteError.badResponse("No response from gateway.") }
        if http.statusCode == 401 { throw RewriteError.signedOut }
        if http.statusCode != 200 {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            if http.statusCode == 429 { throw RewriteError.rateLimited(message ?? "Daily free limit reached.") }
            throw RewriteError.badResponse(message ?? "Gateway error (HTTP \(http.statusCode)).")
        }

        var full = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let err = json["error"] as? String { throw RewriteError.badResponse(err) }
            if let piece = json["text"] as? String, !piece.isEmpty { full += piece; onDelta(piece) }
        }
        let result = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw RewriteError.empty }
        return result
    }

    func verify() async throws -> String {
        guard !token.isEmpty else { throw RewriteError.signedOut }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/health") else {
            throw RewriteError.badResponse("Invalid gateway URL.")
        }
        let (_, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RewriteError.badResponse("Gateway unreachable.")
        }
        return "Connected · free models"
    }
}

/// Email-code sign-in against the gateway.
enum GatewayAuth {
    struct AuthError: LocalizedError { let message: String; var errorDescription: String? { message } }

    static func start(email: String, baseURL: String) async throws {
        try await post("/auth/start", baseURL: baseURL, body: ["email": email])
    }

    /// Returns the issued token.
    static func verify(email: String, code: String, baseURL: String) async throws -> String {
        let json = try await post("/auth/verify", baseURL: baseURL, body: ["email": email, "code": code])
        guard let token = json["token"] as? String, !token.isEmpty else {
            throw AuthError(message: "No token returned.")
        }
        return token
    }

    /// Revokes the token on the gateway and unsubscribes the email (account deletion).
    static func deleteAccount(token: String, baseURL: String) async throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/auth/delete") else {
            throw AuthError(message: "Invalid gateway URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError(message: "No response from gateway.") }
        guard http.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            throw AuthError(message: (json["error"] as? String) ?? "Delete failed (HTTP \(http.statusCode)).")
        }
    }

    @discardableResult
    private static func post(_ path: String, baseURL: String, body: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path) else {
            throw AuthError(message: "Invalid gateway URL. Set it in Settings → Free models → Advanced.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let http = response as? HTTPURLResponse else { throw AuthError(message: "No response from gateway.") }
        guard http.statusCode == 200 else {
            throw AuthError(message: (json["error"] as? String) ?? "Request failed (HTTP \(http.statusCode)).")
        }
        return json
    }
}
