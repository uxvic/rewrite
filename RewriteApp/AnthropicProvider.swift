import Foundation

/// Calls the Anthropic Messages API with streaming (Server-Sent Events).
struct AnthropicProvider: RewriteProvider {
    let apiKey: String
    let model: String

    func stream(text: String,
                systemPrompt: String,
                onDelta: @Sendable @escaping (String) -> Void) async throws -> String {
        guard !apiKey.isEmpty else { throw RewriteError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "stream": true,
            "system": systemPrompt,
            "messages": [["role": "user", "content": text]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RewriteError.badResponse("No HTTP response from Anthropic.")
        }
        guard http.statusCode == 200 else {
            var errData = Data()
            for try await b in bytes { errData.append(b) }
            if let json = try? JSONSerialization.jsonObject(with: errData) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw RewriteError.badResponse("Anthropic error (\(http.statusCode)): \(message)")
            }
            throw RewriteError.badResponse("Anthropic request failed with status \(http.statusCode).")
        }

        var full = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = json["type"] as? String
            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let piece = delta["text"] as? String {
                full += piece
                onDelta(piece)
            } else if type == "error",
                      let error = json["error"] as? [String: Any],
                      let message = error["message"] as? String {
                throw RewriteError.badResponse(message)
            }
        }

        let result = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw RewriteError.empty }
        return result
    }

    func verify() async throws -> String {
        guard !apiKey.isEmpty else { throw RewriteError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "Hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RewriteError.badResponse("No response from Anthropic.")
        }
        if http.statusCode == 200 { return "Connected · \(model)" }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw RewriteError.badResponse("\(message) (HTTP \(http.statusCode))")
        }
        throw RewriteError.badResponse("Anthropic returned HTTP \(http.statusCode).")
    }
}
