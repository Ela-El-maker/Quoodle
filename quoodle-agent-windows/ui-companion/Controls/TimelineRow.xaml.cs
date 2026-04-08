using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Controls;

public sealed partial class TimelineRow : UserControl
{
    public static readonly DependencyProperty TimestampProperty = DependencyProperty.Register(
        nameof(Timestamp), typeof(DateTimeOffset), typeof(TimelineRow), new PropertyMetadata(DateTimeOffset.MinValue, OnVisualChanged));

    public static readonly DependencyProperty SourceProperty = DependencyProperty.Register(
        nameof(Source), typeof(string), typeof(TimelineRow), new PropertyMetadata(string.Empty, OnVisualChanged));

    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(TimelineRow), new PropertyMetadata(string.Empty, OnVisualChanged));

    public static readonly DependencyProperty DetailsProperty = DependencyProperty.Register(
        nameof(Details), typeof(string), typeof(TimelineRow), new PropertyMetadata(string.Empty, OnVisualChanged));

    public static readonly DependencyProperty SeverityProperty = DependencyProperty.Register(
        nameof(Severity), typeof(ActivitySeverity), typeof(TimelineRow), new PropertyMetadata(ActivitySeverity.Info, OnVisualChanged));

    public TimelineRow()
    {
        InitializeComponent();
        Render();
    }

    public DateTimeOffset Timestamp { get => (DateTimeOffset)GetValue(TimestampProperty); set => SetValue(TimestampProperty, value); }
    public string Source { get => (string)GetValue(SourceProperty); set => SetValue(SourceProperty, value); }
    public string Title { get => (string)GetValue(TitleProperty); set => SetValue(TitleProperty, value); }
    public string Details { get => (string)GetValue(DetailsProperty); set => SetValue(DetailsProperty, value); }
    public ActivitySeverity Severity { get => (ActivitySeverity)GetValue(SeverityProperty); set => SetValue(SeverityProperty, value); }

    private static void OnVisualChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        (d as TimelineRow)?.Render();
    }

    private void Render()
    {
        TimeText.Text = Timestamp == DateTimeOffset.MinValue
            ? "--"
            : Timestamp.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss");
        SourceText.Text = Source;
        TitleText.Text = Title;
        DetailsText.Text = Details;
        SeverityText.Text = Severity.ToString();

        var (backgroundKey, foregroundKey) = Severity switch
        {
            ActivitySeverity.Warning => ("ChipWarningBackgroundBrush", "ChipWarningForegroundBrush"),
            ActivitySeverity.Error => ("ChipDangerBackgroundBrush", "ChipDangerForegroundBrush"),
            _ => ("ChipInfoBackgroundBrush", "ChipInfoForegroundBrush")
        };

        if (Application.Current.Resources.TryGetValue(backgroundKey, out var bgObj) && bgObj is Brush bg)
        {
            SeverityPill.Background = bg;
        }

        if (Application.Current.Resources.TryGetValue(foregroundKey, out var fgObj) && fgObj is Brush fg)
        {
            SeverityText.Foreground = fg;
        }
    }
}
