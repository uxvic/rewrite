using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace Rewrite.Providers;

/// Local open-source models via Ollama (http://localhost:11434), streaming NDJSON.
public sealed class OllamaProvider : IRewriteProvider
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };
    private readonly string _host;
    private readonly string _model;

    public OllamaProvider(string host, string model)
    {
        _host = string.IsNullOrWhiteSpace(host) ? "http://localhost:11434" : host.TrimEnd('/');
        _model = string.IsNullOrWhiteSpace(model) ? "llama3.2" : model;
    }

    public async Task<string> StreamAsync(string text, string systemPrompt, Action<string> onDelta, CancellationToken ct)
    {
        var body = new
        {
            model = _model,
            stream = true,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = text }
            }
        };

        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_host}/api/chat");
        req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        HttpResponseMessage resp;
        try
        {
            resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
        }
        catch (HttpRequestException)
        {
            throw new RewriteException(
                "Couldn't reach Ollama at localhost. Make sure Ollama is installed and running, and that you've pulled a model.",
                isSetup: true);
        }

        if (!resp.IsSuccessStatusCode)
        {
            var err = await resp.Content.ReadAsStringAsync(ct);
            throw new RewriteException($"Ollama error ({(int)resp.StatusCode}): {err}");
        }

        var sb = new StringBuilder();
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);
        string? line;
        while ((line = await reader.ReadLineAsync(ct)) is not null)
        {
            ct.ThrowIfCancellationRequested();
            if (line.Length == 0) continue;
            try
            {
                using var doc = JsonDocument.Parse(line);
                if (doc.RootElement.TryGetProperty("message", out var msg) &&
                    msg.TryGetProperty("content", out var content))
                {
                    var s = content.GetString();
                    if (!string.IsNullOrEmpty(s)) { sb.Append(s); onDelta(s); }
                }
            }
            catch (JsonException) { }
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
}
