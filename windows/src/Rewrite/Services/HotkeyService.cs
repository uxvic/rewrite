using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Rewrite.Services;

/// Registers global hotkeys via Win32 RegisterHotKey on a hidden message window:
/// Ctrl+Space toggles the popover; Ctrl+Shift+Space rewrites the current selection
/// in place. Raises the matching event when one fires.
public sealed class HotkeyService : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint VK_SPACE = 0x20;
    private const int ID_TOGGLE = 0x4257;   // arbitrary, distinct
    private const int ID_INPLACE = 0x4258;

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private HwndSource? _source;

    /// Ctrl+Space — open/close the popover.
    public event Action? Pressed;
    /// Ctrl+Shift+Space — rewrite the selected text in place.
    public event Action? InPlacePressed;

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
        RegisterHotKey(_source.Handle, ID_TOGGLE, MOD_CONTROL, VK_SPACE);
        RegisterHotKey(_source.Handle, ID_INPLACE, MOD_CONTROL | MOD_SHIFT, VK_SPACE);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY)
        {
            switch (wParam.ToInt32())
            {
                case ID_TOGGLE:  Pressed?.Invoke();        handled = true; break;
                case ID_INPLACE: InPlacePressed?.Invoke(); handled = true; break;
            }
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_source is null) return;
        UnregisterHotKey(_source.Handle, ID_TOGGLE);
        UnregisterHotKey(_source.Handle, ID_INPLACE);
        _source.RemoveHook(WndProc);
        _source.Dispose();
        _source = null;
    }
}
