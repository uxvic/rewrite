using System.Runtime.InteropServices;
using System.Windows;
using Rewrite.Models;
using Rewrite.Prompts;

namespace Rewrite.Services;

/// Rewrites the user's current selection in whatever app is focused: copy it
/// (Ctrl+C), run the configured in-place action, paste the result (Ctrl+V), then
/// restore the original clipboard. Mirrors the macOS TextReplacementService +
/// AppDelegate.rewriteSelectionInPlace.
public static class TextReplacementService
{
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const byte VK_CONTROL = 0x11;
    private const byte VK_C = 0x43;
    private const byte VK_V = 0x56;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    /// Synthesizes Ctrl+<key> into the focused app.
    private static void SendCtrl(byte key)
    {
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        keybd_event(key, 0, 0, UIntPtr.Zero);
        keybd_event(key, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    // Clipboard access must run on the STA UI thread.
    private static string GetClipboard()
    {
        try { return Clipboard.ContainsText() ? Clipboard.GetText() : ""; }
        catch { return ""; }
    }

    private static void SetClipboard(string s)
    {
        try { if (!string.IsNullOrEmpty(s)) Clipboard.SetText(s); else Clipboard.Clear(); }
        catch { /* clipboard busy */ }
    }

    /// The whole flow runs async; clipboard/key steps are marshaled to the UI thread.
    public static async Task RewriteSelectionAsync(AppSettings settings)
    {
        var ui = Application.Current.Dispatcher;
        string original = await ui.InvokeAsync(GetClipboard);

        // Copy the current selection out of the focused app.
        SendCtrl(VK_C);
        await Task.Delay(140);
        string selection = (await ui.InvokeAsync(GetClipboard)).Trim();
        if (selection.Length == 0)
        {
            await ui.InvokeAsync(() => SetClipboard(original));  // nothing selected — leave clipboard as-was
            return;
        }

        var action = settings.InPlaceAction();
        string result;
        try
        {
            var raw = await settings.MakeProvider()
                .StreamAsync(RewriteActions.Wrap(selection), action.SystemPrompt, _ => { }, CancellationToken.None);
            result = RewriteActions.Clean(raw);
        }
        catch
        {
            await ui.InvokeAsync(() => SetClipboard(original));
            return;
        }
        if (string.IsNullOrWhiteSpace(result))
        {
            await ui.InvokeAsync(() => SetClipboard(original));
            return;
        }

        // Paste the rewrite in place, then put the user's clipboard back.
        await ui.InvokeAsync(() => SetClipboard(result));
        SendCtrl(VK_V);
        await Task.Delay(160);
        await ui.InvokeAsync(() => SetClipboard(original));
        await ui.InvokeAsync(() =>
            settings.AddHistory(action.Label + " (in place)", selection, result, RewriteMode.Writing));
    }
}
