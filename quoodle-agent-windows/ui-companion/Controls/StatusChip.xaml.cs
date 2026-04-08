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

    private static void OnVisualPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        (d as StatusChip)?.Render();
    }

    private void Render()
    {
        ChipText.Text = Label;

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
