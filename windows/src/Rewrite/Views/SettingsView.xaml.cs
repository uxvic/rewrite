using System.Windows;
using System.Windows.Controls;
using Rewrite.ViewModels;

namespace Rewrite.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        // Seed the PasswordBox from the stored key (PasswordBox can't data-bind).
        Loaded += (_, _) => { if (DataContext is ChatViewModel vm) KeyBox.Password = vm.ApiKey; };
    }

    private void KeyBox_Changed(object sender, RoutedEventArgs e)
    {
        if (DataContext is ChatViewModel vm) vm.ApiKey = ((PasswordBox)sender).Password;
    }
}
