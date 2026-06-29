using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using H.NotifyIcon;
using Rewrite.Services;
using Rewrite.Views;

namespace Rewrite;

public partial class App : Application
{
    private TaskbarIcon? _tray;
    private HotkeyService? _hotkey;
    private PopoverWindow? _window;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _window = new PopoverWindow();
        _window.Deactivated += (_, _) => _window.Hide();

        _tray = new TaskbarIcon
        {
            ToolTipText = "Rewrite",
            IconSource = MakeTrayIcon(),
            ContextMenu = BuildMenu()
        };
        _tray.TrayLeftMouseUp += (_, _) => ToggleWindow();
        _tray.ForceCreate();

        _hotkey = new HotkeyService();
        _hotkey.Pressed += ToggleWindow;
        _hotkey.Register();
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();
        var open = new MenuItem { Header = "Open Rewrite" };
        open.Click += (_, _) => ShowWindow();
        var quit = new MenuItem { Header = "Quit Rewrite" };
        quit.Click += (_, _) => Shutdown();
        menu.Items.Add(open);
        menu.Items.Add(new Separator());
        menu.Items.Add(quit);
        return menu;
    }

    private void ToggleWindow()
    {
        if (_window is null) return;
        if (_window.IsVisible) _window.Hide();
        else ShowWindow();
    }

    private void ShowWindow()
    {
        if (_window is null) return;
        var wa = SystemParameters.WorkArea;
        _window.Left = wa.Right - _window.Width - 12;
        _window.Top = wa.Bottom - _window.Height - 12;
        _window.Show();
        _window.Activate();
        _window.FocusComposer();
    }

    /// A simple lavender "R" tile rendered to a bitmap so we don't ship a .ico yet.
    private static ImageSource MakeTrayIcon()
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var bg = new SolidColorBrush(Color.FromRgb(0xA7, 0xA4, 0xF5));
            dc.DrawRoundedRectangle(bg, null, new Rect(0, 0, 32, 32), 7, 7);
            var text = new FormattedText("R", CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
                20, Brushes.White, 1.0);
            dc.DrawText(text, new Point(16 - text.Width / 2, 16 - text.Height / 2));
        }
        var rtb = new RenderTargetBitmap(32, 32, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(visual);
        rtb.Freeze();
        return rtb;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkey?.Dispose();
        _tray?.Dispose();
        base.OnExit(e);
    }
}
