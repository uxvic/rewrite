using System.Windows;
using System.Windows.Input;
using Rewrite.Services;

namespace Rewrite.Views;

/// First-run welcome: the two hotkeys and a short feature tour. Shown once
/// (gated by AppSettings.DidOnboard). Mirrors the macOS WelcomeView.
public partial class WelcomeWindow : Window
{
    public WelcomeWindow() => InitializeComponent();

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        GlassHelper.Apply(this); // acrylic blur + rounded corners + dark mode
    }

    private void Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left) DragMove();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
