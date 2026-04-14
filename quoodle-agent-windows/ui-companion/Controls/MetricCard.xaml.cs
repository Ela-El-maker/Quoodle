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

    public static readonly DependencyProperty DeltaTextProperty = DependencyProperty.Register(
        nameof(DeltaText), typeof(string), typeof(MetricCard), new PropertyMetadata(string.Empty, OnVisualPropertyChanged));

    public static readonly DependencyProperty DeltaToneProperty = DependencyProperty.Register(
        nameof(DeltaTone), typeof(string), typeof(MetricCard), new PropertyMetadata("Success", OnVisualPropertyChanged));

    public static readonly DependencyProperty BadgeTextProperty = DependencyProperty.Register(
        nameof(BadgeText), typeof(string), typeof(MetricCard), new PropertyMetadata(string.Empty, OnVisualPropertyChanged));

    public static readonly DependencyProperty BadgeToneProperty = DependencyProperty.Register(
        nameof(BadgeTone), typeof(string), typeof(MetricCard), new PropertyMetadata("Neutral", OnVisualPropertyChanged));

    public static readonly DependencyProperty StatusTextProperty = DependencyProperty.Register(
        nameof(StatusText), typeof(string), typeof(MetricCard), new PropertyMetadata(string.Empty, OnVisualPropertyChanged));

    public static readonly DependencyProperty StatusToneProperty = DependencyProperty.Register(
        nameof(StatusTone), typeof(string), typeof(MetricCard), new PropertyMetadata("Neutral", OnVisualPropertyChanged));

    public static readonly DependencyProperty ValueFontSizeProperty = DependencyProperty.Register(
        nameof(ValueFontSize), typeof(double), typeof(MetricCard), new PropertyMetadata(28.0, OnVisualPropertyChanged));

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

    public string DeltaText
    {
        get => (string)GetValue(DeltaTextProperty);
        set => SetValue(DeltaTextProperty, value);
    }

    public string DeltaTone
    {
        get => (string)GetValue(DeltaToneProperty);
        set => SetValue(DeltaToneProperty, value);
    }

    public string BadgeText
    {
        get => (string)GetValue(BadgeTextProperty);
        set => SetValue(BadgeTextProperty, value);
    }

    public string BadgeTone
    {
        get => (string)GetValue(BadgeToneProperty);
        set => SetValue(BadgeToneProperty, value);
    }

    public string StatusText
    {
        get => (string)GetValue(StatusTextProperty);
        set => SetValue(StatusTextProperty, value);
    }

    public string StatusTone
    {
        get => (string)GetValue(StatusToneProperty);
        set => SetValue(StatusToneProperty, value);
    }

    public double ValueFontSize
    {
        get => (double)GetValue(ValueFontSizeProperty);
        set => SetValue(ValueFontSizeProperty, value);
    }

    private static void OnVisualPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        (d as MetricCard)?.Render();
    }

    private void Render()
    {
        TitleText.Text = Title;
        ValueText.Text = Value;
        ValueText.FontSize = ValueFontSize;
        SubtitleText.Text = Subtitle;
        GlyphIcon.Glyph = string.IsNullOrWhiteSpace(Glyph) ? "\uE946" : Glyph;

        var tone = (Tone ?? string.Empty).ToLowerInvariant();
        var accentBrush = BrushOf(ResolveToneBrushKey(tone));

        GlyphIcon.Foreground = accentBrush;
        ValueText.Foreground = tone switch
        {
            "success" => BrushOf("SuccessBrush"),
            "danger" => BrushOf("DangerBrush"),
            "info" => BrushOf("InfoBrush"),
            _ => BrushOf("TextPrimaryBrush")
        };

        IconHost.Background = tone switch
        {
            "success" => BrushOf("ChipSuccessBackgroundBrush"),
            "danger" => BrushOf("ChipDangerBackgroundBrush"),
            "info" => BrushOf("ChipInfoBackgroundBrush"),
            "warning" => BrushOf("ChipWarningBackgroundBrush"),
            _ => BrushOf("SurfaceAltBrush")
        };

        CardBorder.BorderBrush = tone switch
        {
            "success" => BrushOf("HeaderPanelBorderBrush"),
            "danger" => BrushOf("DangerBrush"),
            "info" => BrushOf("InfoBrush"),
            "warning" => BrushOf("WarningBrush"),
            _ => BrushOf("BorderBrush")
        };

        CardBorder.Background = tone switch
        {
            "success" => ColorBrush("#110E2A1E"),
            "danger" => ColorBrush("#100F0B12"),
            "info" => ColorBrush("#100A1A2A"),
            _ => BrushOf("SurfaceBrush")
        };

        var hasDelta = !string.IsNullOrWhiteSpace(DeltaText);
        DeltaTextBlock.Visibility = hasDelta ? Visibility.Visible : Visibility.Collapsed;
        DeltaTextBlock.Text = DeltaText;
        DeltaTextBlock.Foreground = BrushOf(ResolveToneBrushKey((DeltaTone ?? "Success").ToLowerInvariant()));

        var hasBadge = !string.IsNullOrWhiteSpace(BadgeText);
        CountBadgeHost.Visibility = hasBadge ? Visibility.Visible : Visibility.Collapsed;
        CountBadgeText.Text = BadgeText;
        ApplyBadgeTone(CountBadgeHost, CountBadgeText, (BadgeTone ?? "Neutral").ToLowerInvariant());

        var hasStatus = !string.IsNullOrWhiteSpace(StatusText);
        StatusBadgeHost.Visibility = hasStatus ? Visibility.Visible : Visibility.Collapsed;
        StatusBadgeText.Text = StatusText;
        ApplyBadgeTone(StatusBadgeHost, StatusBadgeText, (StatusTone ?? "Neutral").ToLowerInvariant());
    }

    private void ApplyBadgeTone(Border host, TextBlock text, string tone)
    {
        (host.Background, text.Foreground) = tone switch
        {
            "success" => (BrushOf("ChipSuccessBackgroundBrush"), BrushOf("ChipSuccessForegroundBrush")),
            "warning" => (BrushOf("ChipWarningBackgroundBrush"), BrushOf("ChipWarningForegroundBrush")),
            "danger" => (BrushOf("ChipDangerBackgroundBrush"), BrushOf("ChipDangerForegroundBrush")),
            "info" => (BrushOf("ChipInfoBackgroundBrush"), BrushOf("ChipInfoForegroundBrush")),
            _ => (BrushOf("ChipNeutralBackgroundBrush"), BrushOf("ChipNeutralForegroundBrush"))
        };
    }

    private static string ResolveToneBrushKey(string tone)
    {
        return tone switch
        {
            "success" => "SuccessBrush",
            "warning" => "WarningBrush",
            "danger" => "DangerBrush",
            "info" => "InfoBrush",
            _ => "BrandBrush"
        };
    }

    private Brush BrushOf(string key)
    {
        return Application.Current.Resources[key] as Brush ?? new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    private static Brush ColorBrush(string hex)
    {
        return new SolidColorBrush(ParseHexColor(hex));
    }

    private static Windows.UI.Color ParseHexColor(string hex)
    {
        var clean = hex.Trim().TrimStart('#');
        if (clean.Length == 6)
        {
            clean = "FF" + clean;
        }

        var a = Convert.ToByte(clean[0..2], 16);
        var r = Convert.ToByte(clean[2..4], 16);
        var g = Convert.ToByte(clean[4..6], 16);
        var b = Convert.ToByte(clean[6..8], 16);
        return Windows.UI.Color.FromArgb(a, r, g, b);
    }
}
