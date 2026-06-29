using System.IO;
using System.Text.Json;
using Rewrite.Models;
using Rewrite.Providers;

namespace Rewrite.Services;

public enum LlmProvider { Anthropic, Ollama }

/// App-wide persisted settings (JSON in %APPDATA%\Rewrite). The API key lives in
/// SecretStore (DPAPI), not here. Mirrors the macOS AppSettings.
public sealed class AppSettings
{
    public static AppSettings Shared { get; } = Load();

    public LlmProvider Provider { get; set; } = LlmProvider.Anthropic;
    public string AnthropicModel { get; set; } = "claude-haiku-4-5";
    public string OllamaHost { get; set; } = "http://localhost:11434";
    public string OllamaModel { get; set; } = "llama3.2";
    public RewriteMode Mode { get; set; } = RewriteMode.Writing;

    /// Smart send on by default (decide-and-act for plain Writing sends).
    public bool SmartIntent { get; set; } = true;
    public bool AutoCopyResult { get; set; }

    public static readonly string[] AnthropicModels =
        { "claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8" };

    // The API key is never serialized — it lives in SecretStore.
    [System.Text.Json.Serialization.JsonIgnore]
    public string ApiKey
    {
        get => SecretStore.Load();
        set => SecretStore.Save(value);
    }

    public IRewriteProvider MakeProvider() => Provider switch
    {
        LlmProvider.Ollama => new OllamaProvider(OllamaHost, OllamaModel),
        _ => new AnthropicProvider(ApiKey, AnthropicModel),
    };

    // MARK: - Persistence

    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Rewrite");
    private static string File_ => Path.Combine(Dir, "settings.json");

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(File_, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* best effort */ }
    }

    private static AppSettings Load()
    {
        try
        {
            if (File.Exists(File_))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(File_)) ?? new AppSettings();
        }
        catch { }
        return new AppSettings();
    }
}
