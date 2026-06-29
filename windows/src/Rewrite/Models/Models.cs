using CommunityToolkit.Mvvm.ComponentModel;

namespace Rewrite.Models;

public enum RewriteMode { Writing, Prompt }

public static class RewriteModeExtensions
{
    public static string Title(this RewriteMode m) => m == RewriteMode.Writing ? "WRITING" : "PROMPT";
    public static string InputPlaceholder(this RewriteMode m) =>
        m == RewriteMode.Writing ? "Type, paste or dictate…" : "Paste a rough prompt…";
}

public enum TurnRole { User, Assistant }

/// One message in the conversation. Assistant turns stream text in; `RawText`
/// holds the raw (tagged) Smart stream while `Text` stays clean for copy/display.
public partial class ChatTurn : ObservableObject
{
    public Guid Id { get; } = Guid.NewGuid();
    public TurnRole Role { get; init; }

    [ObservableProperty] private string _text = "";
    [ObservableProperty] private string _label = "";
    [ObservableProperty] private bool _isStreaming;
    [ObservableProperty] private bool _isError;

    public string RawText { get; set; } = "";
    public string SourceText { get; set; } = "";
    public string SystemPrompt { get; set; } = "";
    public bool FulfillsRequest { get; set; }
    public bool IsSmart { get; set; }

    // Convenience flags for the XAML data templates.
    public bool IsUser => Role == TurnRole.User;
    public bool IsAssistant => Role == TurnRole.Assistant;
}

/// One past rewrite kept for the history panel (M2).
public sealed record HistoryItem(string Id, string ActionLabel, string Input, string Output, RewriteMode Mode);
