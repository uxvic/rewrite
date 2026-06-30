using System.Windows;
using System.Windows.Input;
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
}
