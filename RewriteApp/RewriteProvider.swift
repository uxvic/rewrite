import Foundation

/// Abstraction over an LLM backend. Concrete implementations (Anthropic, Ollama,
/// Claude Code) take a system prompt + the user's text and stream back the
/// rewritten text. `onDelta` is called with incremental pieces as they arrive;
/// the full result is returned at the end. Honors task cancellation.
protocol RewriteProvider {
    func stream(text: String,
                systemPrompt: String,
                onDelta: @Sendable @escaping (String) -> Void) async throws -> String

    /// Lightweight connectivity/auth check. Returns a short success detail
    /// (e.g. model or version) or throws a `RewriteError` explaining why not.
    func verify() async throws -> String
}

enum RewriteError: LocalizedError {
    case missingAPIKey
    case badResponse(String)
    case ollamaUnreachable
    case claudeCodeNotFound
    case claudeCodeFailed(String)
    case signedOut
    case rateLimited(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Anthropic API key set. Open Settings and paste your key (or switch to the free Ollama provider)."
        case .signedOut:
            return "Sign in to use the free models. Open Settings → Free models and enter your email."
        case .rateLimited(let message):
            return message
        case .badResponse(let message):
            return message
        case .ollamaUnreachable:
            return "Couldn't reach Ollama at localhost. Make sure Ollama is installed and running (`ollama serve`), and that you've pulled a model (`ollama pull llama3.2`)."
        case .claudeCodeNotFound:
            return "Couldn't find the `claude` command. Install Claude Code (curl -fsSL https://claude.ai/install.sh | bash), or set its full path in Settings."
        case .claudeCodeFailed(let detail):
            return "Claude Code error: \(detail)\n\nIf this mentions login/auth, run `claude` once in Terminal and log in with your subscription."
        case .empty:
            return "The model returned an empty response. Try again."
        }
    }
}
