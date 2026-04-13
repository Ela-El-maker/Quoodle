using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Quoodle.Agent.UiCompanion.Controls;

public sealed partial class MetricCard : UserControl
{
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(MetricCard), new PropertyMetadata(string.Empty, OnVisualPropertyChanged));

    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value), typeof(string), typeof(MetricCard), new PropertyMetadata("--", OnVisualPropertyChanged));

    public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(
        nameof(Subtitle), typeof(string), typeof(MetricCard), new PropertyMetadata(string.Empty, OnVisualPropertyChanged));

    public static readonly DependencyProperty ToneProperty = DependencyProperty.Register(
        nameof(Tone), typeof(string), typeof(MetricCard), new PropertyMetadata("Neutral", OnVisualPropertyChanged));

    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph), typeof(string), typeof(MetricCard), new PropertyMetadata("\uE946", OnVisualPropertyChanged));

    public MetricCard()
    {
        InitializeComponent();
        Render();
    }

    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Value
    {
        get => (string)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    public string Subtitle
    {
        get => (string)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    public string Tone
    {
        get => (string)GetValue(ToneProperty);
        set => SetValue(ToneProperty, value);
    }

    public string Glyph
    {
        get => (string)GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    private static void OnVisualPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        (d as MetricCard)?.Render();
    }

    private void Render()
    {
        TitleText.Text = Title;
        ValueText.Text = Value;
        SubtitleText.Text = Subtitle;
        GlyphIcon.Glyph = string.IsNullOrWhiteSpace(Glyph) ? "\uE946" : Glyph;

        var tone = (Tone ?? string.Empty).ToLowerInvariant();
        var accentKey = tone switch
        {
            "success" => "SuccessBrush",
            "warning" => "WarningBrush",
            "danger" => "DangerBrush",
            "info" => "InfoBrush",
            _ => "BrandBrush"
        };

        if (Application.Current.Resources.TryGetValue(accentKey, out var accentObj) && accentObj is Brush accentBrush)
        {
            GlyphIcon.Foreground = accentBrush;
            CardBorder.BorderBrush = tone switch
            {
                "success" => Application.Current.Resources["HeaderPanelBorderBrush"] as Brush ?? accentBrush,
                "info" => Application.Current.Resources["BorderBrush"] as Brush ?? accentBrush,
                "warning" => Application.Current.Resources["BorderBrush"] as Brush ?? accentBrush,
                "danger" => Application.Current.Resources["DangerBrush"] as Brush ?? accentBrush,
                _ => Application.Current.Resources["BorderBrush"] as Brush ?? accentBrush
            };
            CardBorder.BorderThickness = new Thickness(1);
        }
    }
}
