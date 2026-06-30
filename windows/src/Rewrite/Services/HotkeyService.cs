using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Rewrite.Services;

/// Registers a global hotkey (Ctrl+Space) via Win32 RegisterHotKey on a hidden
/// message window, and raises Pressed when it fires.
public sealed class HotkeyService : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_CONTROL = 0x0002;
    private const uint VK_SPACE = 0x20;
    private const int HOTKEY_ID = 0x4257; // arbitrary

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private HwndSource? _source;
    public event Action? Pressed;

    public void Register()
    {
        var parameters = new HwndSourceParameters("RewriteHotkeyWindow")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
        RegisterHotKey(_source.Handle, HOTKEY_ID, MOD_CONTROL, VK_SPACE);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
        {
            Pressed?.Invoke();
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_source is null) return;
        UnregisterHotKey(_source.Handle, HOTKEY_ID);
        _source.RemoveHook(WndProc);
        _source.Dispose();
        _source = null;
    }
}
