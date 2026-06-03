import Foundation

/// Calls a locally running Ollama server with streaming (NDJSON). Free + private.
struct OllamaProvider: RewriteProvider {
    let host: String
    let model: String

    func stream(text: String,
                systemPrompt: String,
                onDelta: @Sendable @escaping (String) -> Void) async throws -> String {
        guard let url = URL(string: host.trimmingCharacters(in: .whitespaces) + "/api/chat") else {
            throw RewriteError.badResponse("Invalid Ollama host URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw RewriteError.ollamaUnreachable
        }
        guard let http = response as? HTTPURLResponse else { throw RewriteError.ollamaUnreachable }
        guard http.statusCode == 200 else {
            throw RewriteError.badResponse("Ollama request failed with status \(http.statusCode).")
        }

        var full = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let message = json["message"] as? [String: Any],
               let piece = message["content"] as? String, !piece.isEmpty {
                full += piece
                onDelta(piece)
            }
            if json["done"] as? Bool == true { break }
        }

        let result = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw RewriteError.empty }
        return result
    }

    func verify() async throws -> String {
        guard let url = URL(string: host.trimmingCharacters(in: .whitespaces) + "/api/tags") else {
            throw RewriteError.badResponse("Invalid Ollama host URL.")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw RewriteError.ollamaUnreachable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RewriteError.ollamaUnreachable
        }
        let names: [String] = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { ($0?["models"] as? [[String: Any]]) }?
            .compactMap { $0["name"] as? String } ?? []
        let wanted = model.trimmingCharacters(in: .whitespaces)
        let hasModel = names.contains { $0 == wanted || $0.hasPrefix(wanted + ":") }
        if hasModel { return "Connected · \(wanted)" }
        throw RewriteError.badResponse("Ollama is running, but the model “\(wanted)” isn't installed. Run: ollama pull \(wanted)")
    }
}
