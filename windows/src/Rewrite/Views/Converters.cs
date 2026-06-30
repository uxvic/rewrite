using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace Rewrite.Views;

internal static class Brushes2
{
    public static readonly SolidColorBrush Accent = Freeze(Color.FromRgb(0xA7, 0xA4, 0xF5));
    public static readonly SolidColorBrush Ink = Freeze(Color.FromRgb(0x1B, 0x17, 0x26));
    public static readonly SolidColorBrush Primary = Freeze(Color.FromRgb(0xF2, 0xF3, 0xF7));
    public static readonly SolidColorBrush Glass = Freeze(Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF));
    public static readonly SolidColorBrush UserBubble = Freeze(Color.FromArgb(0x40, 0x3A, 0x3A, 0x46));
    public static readonly SolidColorBrush AssistantBubble = Freeze(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF));
    public static readonly SolidColorBrush Error = Freeze(Color.FromRgb(0xFF, 0x6B, 0x5E));
    private static SolidColorBrush Freeze(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
}

/// True when value[0].Equals(value[1]) — used to mark the selected action chip.
public sealed class EqualityMultiConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object? parameter, CultureInfo culture)
        => values.Length == 2 && Equals(values[0], values[1]);
    public object[] ConvertBack(object value, Type[] t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// IsUser → HorizontalAlignment (user bubbles right, assistant left).
public sealed class UserAlignConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => (value is true) ? HorizontalAlignment.Right : HorizontalAlignment.Left;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class InverseBoolConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value is not true;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => value is not true;
}

public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => (value is true) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// True only when ALL bound bools are true (e.g. assistant && !streaming).
public sealed class AndToVisibilityConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object? parameter, CultureInfo culture)
        => values.All(v => v is true) ? Visibility.Visible : Visibility.Collapsed;
    public object[] ConvertBack(object value, Type[] t, object? p, CultureInfo c) => throw new NotSupportedException();
}

public sealed class NonEmptyToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => string.IsNullOrWhiteSpace(value as string) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// bool → accent (on) or glass (off); parameter "ink" returns the matching text colour.
public sealed class BoolToBrushConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var on = value is true;
        return (parameter as string) == "ink"
            ? (on ? Brushes2.Ink : Brushes2.Primary)
            : (on ? (Brush)Brushes2.Accent : Brushes2.Glass);
    }
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// (selectedId, thisId) → accent/glass (or ink/primary text with parameter "ink").
public sealed class SelectedToBrushConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object? parameter, CultureInfo culture)
    {
        var selected = values.Length == 2 && Equals(values[0], values[1]);
        return (parameter as string) == "ink"
            ? (selected ? Brushes2.Ink : Brushes2.Primary)
            : (selected ? (Brush)Brushes2.Accent : Brushes2.Glass);
    }
    public object[] ConvertBack(object value, Type[] t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// IsUser → bubble brush.
public sealed class BubbleBrushConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => (value is true) ? Brushes2.UserBubble : Brushes2.AssistantBubble;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// IsError → red, else primary text.
public sealed class ErrorBrushConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => (value is true) ? Brushes2.Error : Brushes2.Primary;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// enum value → Visible when its name equals the parameter, else Collapsed.
public sealed class EnumToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => string.Equals(value?.ToString(), parameter as string, StringComparison.Ordinal)
            ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// enum value → Collapsed when its name equals the parameter, else Visible.
public sealed class EnumNotToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => string.Equals(value?.ToString(), parameter as string, StringComparison.Ordinal)
            ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}

/// Mode segment: parameter "Writing"/"Prompt" → accent fill when selected else
/// transparent; parameter "Writing.ink"/"Prompt.ink" → ink/secondary text colour.
public sealed class ModeBrushConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        var p = parameter as string ?? "";
        var ink = p.EndsWith(".ink");
        var mode = ink ? p[..^4] : p;
        var selected = string.Equals(value?.ToString(), mode, StringComparison.Ordinal);
        if (ink) return selected ? Brushes2.Ink : Brushes2.Primary;
        return selected ? (Brush)Brushes2.Accent : System.Windows.Media.Brushes.Transparent;
    }
    public object ConvertBack(object? value, Type t, object? p, CultureInfo c) => throw new NotSupportedException();
}
