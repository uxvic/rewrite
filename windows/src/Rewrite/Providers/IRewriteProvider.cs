namespace Rewrite.Providers;

/// Abstraction over an LLM backend. Mirrors the macOS RewriteProvider protocol:
/// takes a system prompt + the user's text and streams back the result.
/// `onDelta` is called with incremental pieces; the full result is returned.
public interface IRewriteProvider
{
    Task<string> StreamAsync(string text, string systemPrompt, Action<string> onDelta, CancellationToken ct);

    /// Lightweight connectivity/auth check — returns a short success detail or throws.
    Task<string> VerifyAsync(CancellationToken ct);
}

/// Errors that map to a friendly inline message (mirrors RewriteError).
public sealed class RewriteException : Exception
{
    public bool IsSetup { get; }
    public RewriteException(string message, bool isSetup = false) : base(message) => IsSetup = isSetup;
}
