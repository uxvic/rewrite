using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Rewrite.Providers;

/// Claude via the Anthropic Messages API (streaming SSE).
public sealed class AnthropicProvider : IRewriteProvider
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(3) };
    private readonly string _apiKey;
    private readonly string _model;

    public AnthropicProvider(string apiKey, string model)
    {
        _apiKey = apiKey;
        _model = string.IsNullOrWhiteSpace(model) ? "claude-haiku-4-5" : model;
    }

    public async Task<string> StreamAsync(string text, string systemPrompt, Action<string> onDelta, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_apiKey))
            throw new RewriteException("No Anthropic API key set. Open Settings and paste your key.", isSetup: true);

        var body = new
        {
            model = _model,
            max_tokens = 2048,
            system = systemPrompt,
            stream = true,
            messages = new[] { new { role = "user", content = text } }
        };

        using var req = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
        req.Headers.TryAddWithoutValidation("x-api-key", _apiKey);
        req.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
        req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        using var resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!resp.IsSuccessStatusCode)
        {
            var err = await resp.Content.ReadAsStringAsync(ct);
            if ((int)resp.StatusCode == 401)
                throw new RewriteException("Anthropic rejected the API key. Check it in Settings.", isSetup: true);
            throw new RewriteException($"Anthropic error ({(int)resp.StatusCode}): {Truncate(err)}");
        }

        var sb = new StringBuilder();
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);
        string? line;
        while ((line = await reader.ReadLineAsync(ct)) is not null)
        {
            ct.ThrowIfCancellationRequested();
            if (!line.StartsWith("data:")) continue;
            var json = line["data:".Length..].Trim();
            if (json.Length == 0 || json == "[DONE]") continue;

            try
            {
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                if (root.TryGetProperty("type", out var type) &&
                    type.GetString() == "content_block_delta" &&
                    root.TryGetProperty("delta", out var delta) &&
                    delta.TryGetProperty("text", out var piece))
                {
                    var s = piece.GetString();
                    if (!string.IsNullOrEmpty(s)) { sb.Append(s); onDelta(s); }
                }
            }
            catch (JsonException) { /* ignore keep-alive / partial frames */ }
        }

        var full = sb.ToString();
        if (string.IsNullOrWhiteSpace(full))
            throw new RewriteException("The model returned an empty response. Try again.");
        return full;
    }

    public async Task<string> VerifyAsync(CancellationToken ct)
    {
        var sb = new StringBuilder();
        await StreamAsync("ping", "Reply with the single word: ok", s => sb.Append(s), ct);
        return $"Connected · {_model}";
    }

    private static string Truncate(string s) => s.Length <= 300 ? s : s[..300] + "…";
}
