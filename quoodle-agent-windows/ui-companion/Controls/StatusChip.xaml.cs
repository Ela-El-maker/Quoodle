using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Quoodle.Agent.UiCompanion.Controls;

public sealed partial class StatusChip : UserControl
{
    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label),
        typeof(string),
        typeof(StatusChip),
        new PropertyMetadata("Unknown", OnVisualPropertyChanged));

    public static readonly DependencyProperty ToneProperty = DependencyProperty.Register(
        nameof(Tone),
        typeof(string),
        typeof(StatusChip),
        new PropertyMetadata("Neutral", OnVisualPropertyChanged));

    public static readonly DependencyProperty CompactProperty = DependencyProperty.Register(
        nameof(Compact),
        typeof(bool),
        typeof(StatusChip),
        new PropertyMetadata(false, OnVisualPropertyChanged));

    public StatusChip()
    {
        InitializeComponent();
        Render();
    }

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public string Tone
    {
        get => (string)GetValue(ToneProperty);
        set => SetValue(ToneProperty, value);
    }

    public bool Compact
    {
        get => (bool)GetValue(CompactProperty);
        set => SetValue(CompactProperty, value);
    }

    private static void OnVisualPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        (d as StatusChip)?.Render();
    }

    private void Render()
    {
        ChipText.Text = Label;

        if (Compact)
        {
            ChipBorder.Padding = new Thickness(8, 3, 8, 3);
            ChipBorder.CornerRadius = new CornerRadius(8);
            ToneDot.Width = 7;
            ToneDot.Height = 7;
            ChipText.FontSize = 12;
            ChipContent.Spacing = 5;
        }
        else
        {
            ChipBorder.Padding = new Thickness(12, 6, 12, 6);
            ChipBorder.CornerRadius = new CornerRadius(16);
            ToneDot.Width = 9;
            ToneDot.Height = 9;
            ChipText.FontSize = 13;
            ChipContent.Spacing = 7;
        }

        var normalizedTone = (Tone ?? string.Empty).ToLowerInvariant();
        var (backgroundKey, foregroundKey) = normalizedTone switch
        {
            "success" => ("ChipSuccessBackgroundBrush", "ChipSuccessForegroundBrush"),
            "warning" => ("ChipWarningBackgroundBrush", "ChipWarningForegroundBrush"),
            "danger" => ("ChipDangerBackgroundBrush", "ChipDangerForegroundBrush"),
            "info" => ("ChipInfoBackgroundBrush", "ChipInfoForegroundBrush"),
            _ => ("ChipNeutralBackgroundBrush", "ChipNeutralForegroundBrush")
        };

        if (Application.Current.Resources.TryGetValue(backgroundKey, out var bgObj) && bgObj is Brush background)
        {
            ChipBorder.Background = background;
        }

        if (Application.Current.Resources.TryGetValue(foregroundKey, out var fgObj) && fgObj is Brush foreground)
        {
            ChipText.Foreground = foreground;
            ToneDot.Fill = foreground;
        }
    }
}
