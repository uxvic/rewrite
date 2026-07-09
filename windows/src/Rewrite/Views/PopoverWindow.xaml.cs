using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Rewrite.Models;
using Rewrite.Services;
using Rewrite.ViewModels;

namespace Rewrite.Views;

public partial class PopoverWindow : Window
{
    public PopoverWindow()
    {
        InitializeComponent();
        DataContext = new ChatViewModel();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        GlassHelper.Apply(this); // acrylic blur + rounded corners + dark mode
    }

    public void FocusComposer()
    {
        Composer.Focus();
        Composer.CaretIndex = Composer.Text?.Length ?? 0;
    }

    public void ShowSettings()
    {
        if (DataContext is ChatViewModel vm) vm.CurrentPane = Pane.Settings;
    }

    /// True while the user has pinned the window (keep open on focus loss).
    public bool IsPinned => (DataContext as ChatViewModel)?.IsPinned ?? false;

    /// Drag the header (its empty area) to reposition the floating window.
    private void Header_Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left) DragMove();
    }

    private void Composer_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        // Enter sends; Shift+Enter inserts a newline.
        if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0)
        {
            e.Handled = true;
            if (DataContext is ChatViewModel vm && vm.SendCommand.CanExecute(null))
                vm.SendCommand.Execute(null);
        }
        else if (e.Key == Key.Escape)
        {
            e.Handled = true;
            Hide();
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Hide();

    /// Open the Retry menu, capturing which bubble it belongs to (a WPF ContextMenu
    /// lives outside the visual tree, so we set its DataContext to the view model).
    private void Retry_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: ChatTurn turn } btn) return;
        if (DataContext is not ChatViewModel vm) return;
        vm.SetRetryTarget(turn);
        if (btn.ContextMenu is { } menu)
        {
            menu.DataContext = vm;
            menu.PlacementTarget = btn;
            menu.IsOpen = true;
        }
    }
}
