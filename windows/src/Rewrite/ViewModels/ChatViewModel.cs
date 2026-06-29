using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Rewrite.Models;
using Rewrite.Prompts;
using Rewrite.Providers;
using Rewrite.Services;

namespace Rewrite.ViewModels;

/// Drives the chat: send pipeline, Smart decide-and-act, modes, per-mode threads,
/// shared draft. Mirrors the macOS PopoverView logic.
public partial class ChatViewModel : ObservableObject
{
    private readonly Dictionary<RewriteMode, ObservableCollection<ChatTurn>> _threads = new();
    private readonly AppSettings _settings = AppSettings.Shared;
    private CancellationTokenSource? _cts;

    public ChatViewModel()
    {
        foreach (RewriteMode m in Enum.GetValues<RewriteMode>())
            _threads[m] = new ObservableCollection<ChatTurn>();
        _mode = _settings.Mode;
        _smartIntent = _settings.SmartIntent;
    }

    // MARK: - Bound state

    [ObservableProperty] private RewriteMode _mode;
    partial void OnModeChanged(RewriteMode value)
    {
        _settings.Mode = value; _settings.Save();
        SelectedActionId = null;
        OnPropertyChanged(nameof(Thread));
        OnPropertyChanged(nameof(Actions));
        OnPropertyChanged(nameof(IsWriting));
        OnPropertyChanged(nameof(SmartActive));
    }

    [ObservableProperty] private string _draft = "";
    partial void OnDraftChanged(string value) { OnPropertyChanged(nameof(CanSend)); SendCommand.NotifyCanExecuteChanged(); }

    [ObservableProperty] private bool _smartIntent;
    partial void OnSmartIntentChanged(bool value) { _settings.SmartIntent = value; _settings.Save(); OnPropertyChanged(nameof(SmartActive)); }

    [ObservableProperty] private string? _selectedActionId;
    partial void OnSelectedActionIdChanged(string? value) => OnPropertyChanged(nameof(SmartActive));

    [ObservableProperty] private bool _isLoading;
    partial void OnIsLoadingChanged(bool value) { OnPropertyChanged(nameof(CanSend)); SendCommand.NotifyCanExecuteChanged(); }

    // MARK: - Derived

    public ObservableCollection<ChatTurn> Thread => _threads[Mode];
    public bool IsWriting => Mode == RewriteMode.Writing;
    public IReadOnlyList<PresetAction> Actions => Mode == RewriteMode.Writing ? RewriteActions.Writing : RewriteActions.PromptMode;
    /// True when Smart is the active choice (highlight), mutually exclusive with picked actions.
    public bool SmartActive => SmartIntent && SelectedActionId == null && IsWriting;
    public bool CanSend => !string.IsNullOrWhiteSpace(Draft) && !IsLoading;

    // MARK: - Commands

    [RelayCommand]
    private void ToggleSmart()
    {
        var wasActive = SmartActive;
        SelectedActionId = null;
        SmartIntent = !wasActive;
    }

    [RelayCommand]
    private void SelectAction(string id) => SelectedActionId = SelectedActionId == id ? null : id;

    [RelayCommand]
    private void SetMode(string mode) => Mode = mode == "Prompt" ? RewriteMode.Prompt : RewriteMode.Writing;

    [RelayCommand]
    private void NewChat()
    {
        _cts?.Cancel();
        IsLoading = false;
        Thread.Clear();
        Draft = "";
        SelectedActionId = null;
    }

    [RelayCommand] private void Stop() => _cts?.Cancel();

    [RelayCommand]
    private void Copy(ChatTurn turn) => TrySetClipboard(turn.Text);

    [RelayCommand]
    private void Retry(ChatTurn turn) =>
        Run(turn.SystemPrompt, turn.Label, smart: turn.IsSmart, wrap: !turn.FulfillsRequest, source: turn.SourceText, variation: true);

    [RelayCommand(CanExecute = nameof(CanSend))]
    private void Send()
    {
        var t = Draft.Trim();
        if (t.Length == 0) return;

        // Smart plain send (Writing, no explicit action) → decide-and-act.
        if (SelectedActionId == null && IsWriting && SmartIntent)
        {
            AddUserTurn(t);
            Run(null, "Improve", smart: true);
            return;
        }
        var sel = ResolveAction();
        AddUserTurn(t);
        Run(sel.SystemPrompt, sel.Label);
    }

    // MARK: - Pipeline

    private void AddUserTurn(string text)
    {
        Thread.Add(new ChatTurn { Role = TurnRole.User, Text = text });
        Draft = "";
    }

    private void Run(string? systemPrompt, string label, bool smart = false, bool wrap = true,
                     string? source = null, bool variation = false)
    {
        var src = (source ?? LatestUserText()).Trim();
        if (src.Length == 0) return;
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        IsLoading = true;

        var prompt = smart ? RewriteActions.SmartSystemPrompt : (systemPrompt ?? "");
        var turn = new ChatTurn
        {
            Role = TurnRole.Assistant,
            Label = label,
            IsStreaming = true,
            SourceText = src,
            SystemPrompt = prompt,
            IsSmart = smart,
            FulfillsRequest = !wrap && !smart
        };
        Thread.Add(turn);

        var provider = _settings.MakeProvider();
        var payload = smart ? (SmartContextPayload() ?? src) : (wrap ? RewriteActions.Wrap(src) : src);
        if (variation) payload += "\n\n(Give a noticeably different alternative version.)";

        _ = StreamBody(turn, payload, prompt, label, provider, parseTag: smart, ct);
    }

    private async Task StreamBody(ChatTurn turn, string payload, string systemPrompt, string label,
                                  IRewriteProvider provider, bool parseTag, CancellationToken ct)
    {
        var dispatcher = Application.Current.Dispatcher;
        try
        {
            var raw = await provider.StreamAsync(payload, systemPrompt, piece =>
            {
                dispatcher.BeginInvoke(() =>
                {
                    if (parseTag)
                    {
                        turn.RawText += piece;
                        var p = RewriteActions.ParseSmart(turn.RawText);
                        if (p.Label != null) { turn.Label = p.Label; turn.FulfillsRequest = p.Label == "Request"; }
                        turn.Text = p.Body;
                    }
                    else turn.Text += piece;
                });
            }, ct);

            dispatcher.Invoke(() =>
            {
                if (parseTag)
                {
                    var p = RewriteActions.ParseSmart(raw);
                    turn.Text = p.Body;
                    turn.Label = p.Label ?? label;
                    turn.FulfillsRequest = p.Label == "Request";
                }
                else turn.Text = RewriteActions.Clean(raw);
                turn.IsStreaming = false;
                IsLoading = false;
                if (_settings.AutoCopyResult) TrySetClipboard(turn.Text);
            });
        }
        catch (OperationCanceledException)
        {
            dispatcher.Invoke(() =>
            {
                IsLoading = false;
                if (string.IsNullOrEmpty(turn.Text)) Thread.Remove(turn);
                else turn.IsStreaming = false;
            });
        }
        catch (Exception ex)
        {
            dispatcher.Invoke(() =>
            {
                IsLoading = false;
                turn.Text = ex.Message;
                turn.IsStreaming = false;
                turn.IsError = true;
            });
        }
    }

    /// Transcript of the conversation so a Smart follow-up refines, not restarts.
    private string? SmartContextPayload()
    {
        var turns = Thread
            .Where(t => (t.Role == TurnRole.User || t.Role == TurnRole.Assistant) && !string.IsNullOrWhiteSpace(t.Text))
            .ToList();
        if (turns.Count <= 1) return null;
        var transcript = string.Join("\n\n",
            turns.Select(t => t.Role == TurnRole.User ? $"User: {t.Text}" : $"You: {t.Text}"));
        return
            "Below is the conversation so far. The final \"User:\" line is a new follow-up — treat it as a " +
            "continuation of this conversation (typically a refinement of, or addition to, what you last wrote " +
            "under \"You:\"), not a brand-new standalone task. Produce the updated result.\n\n" + transcript;
    }

    private string LatestUserText()
    {
        for (var i = Thread.Count - 1; i >= 0; i--)
            if (Thread[i].Role == TurnRole.User) return Thread[i].Text.Trim();
        return "";
    }

    private PresetAction ResolveAction()
    {
        if (SelectedActionId != null)
        {
            var found = Actions.FirstOrDefault(a => a.Id == SelectedActionId);
            if (found != null) return found;
        }
        return Mode == RewriteMode.Writing ? RewriteActions.WritingDefault : RewriteActions.PromptDefault;
    }

    private static void TrySetClipboard(string s)
    {
        try { Clipboard.SetText(s); } catch { /* clipboard busy */ }
    }
}
