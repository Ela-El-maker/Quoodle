using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Quoodle.Agent.UiCompanion.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.ComponentModel;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class DashboardPage : Page
{
    private readonly DashboardViewModel _vm;

    public DashboardPage()
    {
        InitializeComponent();
        _vm = new DashboardViewModel(App.StateStore);
        _vm.PropertyChanged += HandleViewModelPropertyChanged;
        Unloaded += OnPageUnloaded;

        Render();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        QueueRender();
    }

    private void QueueRender()
    {
        if (DispatcherQueue.HasThreadAccess)
        {
            Render();
            return;
        }

        _ = DispatcherQueue.TryEnqueue(Render);
    }

    private void Render()
    {
        RenderHero();
        RenderCards();
        RenderTelemetryPanel();
        RenderCommandPanel();
        RenderLastCommandPanel();
        RenderFeed();
    }

    private void RenderHero()
    {
        ConnectionText.Text = _vm.ConnectionLabel;
        SessionText.Text = _vm.SessionId;
        DeviceText.Text = _vm.DeviceLabel;
        HeartbeatText.Text = _vm.HeartbeatAge;
        AgentVersionText.Text = _vm.AgentVersion;
        OsBuildText.Text = _vm.OsBuild;
        HwidHashText.Text = _vm.HwidHash;
        PolicyHashText.Text = _vm.PolicyHash;
        EndpointText.Text = _vm.WssEndpoint;
        ReconnectText.Text = _vm.ReconnectAttempts;

        var toneBrush = BrushOf(ToneToBrushKey(_vm.ConnectionTone));
        HeroPanel.BorderBrush = toneBrush;
        ConnectionDot.Fill = toneBrush;
        ConnectionText.Foreground = toneBrush;
    }

    private void RenderCards()
    {
        ApplyCard(WssUptimeCard, _vm.WssUptimeCard);
        ApplyCard(LastHeartbeatCard, _vm.LastHeartbeatCard);
        ApplyCard(FailedCommandsCard, _vm.FailedCommandsCard);
        ApplyCard(CommandsCompletedCard, _vm.CommandsCompletedCard);
        ApplyCard(KernelEventsCard, _vm.KernelEventsCard);
        ApplyCard(CpuUsageCard, _vm.CpuUsageCard);
        ApplyCard(RamUsageCard, _vm.RamUsageCard);
        ApplyCard(DiskUsageCard, _vm.DiskUsageCard);
        ApplyCard(NetTxCard, _vm.NetTxCard);
        ApplyCard(NetRxCard, _vm.NetRxCard);
        ApplyCard(TelemetrySnapshotsCard, _vm.TelemetrySnapshotsCard);
    }

    private void RenderTelemetryPanel()
    {
        TelemetrySubtitleText.Text = _vm.TelemetryMode == TelemetryChartMode.CpuRam
            ? "telemetry_basic - last 90 minutes"
            : "telemetry_network - last 90 minutes";

        ApplySegmentButtonVisual(CpuRamTabButton, _vm.IsCpuRamMode);
        ApplySegmentButtonVisual(NetworkTabButton, _vm.IsNetworkMode);

        RenderTelemetryChart();
    }

    private void RenderTelemetryChart()
    {
        TelemetryChartCanvas.Children.Clear();
        TelemetryXAxisGrid.Children.Clear();
        TelemetryXAxisGrid.ColumnDefinitions.Clear();

        var points = _vm.TelemetrySeries;
        if (points.Count < 2 || TelemetryChartCanvas.ActualWidth < 120)
        {
            TelemetryEmptyText.Visibility = Visibility.Visible;
            return;
        }

        TelemetryEmptyText.Visibility = Visibility.Collapsed;

        var width = Math.Max(220, TelemetryChartCanvas.ActualWidth);
        var height = TelemetryChartCanvas.Height;
        var topPadding = 16.0;
        var bottomPadding = 22.0;
        var usableHeight = height - topPadding - bottomPadding;

        DrawGridLines(TelemetryChartCanvas, width, height, 3);

        var primary = _vm.IsCpuRamMode
            ? points.Select(x => (double)x.Cpu).ToList()
            : points.Select(x => x.NetTx).ToList();
        var secondary = _vm.IsCpuRamMode
            ? points.Select(x => (double)x.Ram).ToList()
            : points.Select(x => x.NetRx).ToList();

        var all = primary.Concat(secondary).ToList();
        var max = Math.Max(1, all.Max());
        var min = Math.Min(0, all.Min());
        if (Math.Abs(max - min) < 0.1)
        {
            max = min + 1;
        }

        var primaryStroke = _vm.IsCpuRamMode ? BrushOf("SuccessBrush") : BrushOf("InfoBrush");
        var secondaryStroke = _vm.IsCpuRamMode ? BrushOf("InfoBrush") : BrushOf("SuccessBrush");

        DrawLineSeries(TelemetryChartCanvas, primary, width, usableHeight, topPadding, min, max, primaryStroke);
        DrawLineSeries(TelemetryChartCanvas, secondary, width, usableHeight, topPadding, min, max, secondaryStroke);

        var labelCount = Math.Min(11, points.Count);
        BuildXAxis(TelemetryXAxisGrid, points, labelCount);
    }

    private void RenderCommandPanel()
    {
        RenderCommandChart();
    }

    private void RenderCommandChart()
    {
        CommandChartCanvas.Children.Clear();
        CommandXAxisGrid.Children.Clear();
        CommandXAxisGrid.ColumnDefinitions.Clear();

        var bins = _vm.CommandBins;
        if (bins.Count == 0 || CommandChartCanvas.ActualWidth < 120)
        {
            return;
        }

        var width = Math.Max(220, CommandChartCanvas.ActualWidth);
        var height = CommandChartCanvas.Height;
        var topPadding = 16.0;
        var bottomPadding = 22.0;
        var usableHeight = height - topPadding - bottomPadding;
        DrawGridLines(CommandChartCanvas, width, height, 4);

        var maxValue = Math.Max(1, bins.Max(x => Math.Max(x.Completed, x.Failed)));
        var plotWidth = width - 22;
        var groupWidth = plotWidth / bins.Count;

        for (var i = 0; i < bins.Count; i++)
        {
            var x = 12 + i * groupWidth;
            var completedHeight = usableHeight * bins[i].Completed / maxValue;
            var failedHeight = usableHeight * bins[i].Failed / maxValue;

            var completedBar = new Rectangle
            {
                Width = Math.Max(6, groupWidth * 0.34),
                Height = completedHeight,
                RadiusX = 2,
                RadiusY = 2,
                Fill = BrushOf("SuccessBrush"),
                Opacity = 0.88
            };
            Canvas.SetLeft(completedBar, x + groupWidth * 0.10);
            Canvas.SetTop(completedBar, topPadding + usableHeight - completedHeight);
            CommandChartCanvas.Children.Add(completedBar);

            var failedBar = new Rectangle
            {
                Width = Math.Max(4, groupWidth * 0.26),
                Height = failedHeight,
                RadiusX = 2,
                RadiusY = 2,
                Fill = BrushOf("DangerBrush"),
                Opacity = 0.92
            };
            Canvas.SetLeft(failedBar, x + groupWidth * 0.52);
            Canvas.SetTop(failedBar, topPadding + usableHeight - failedHeight);
            CommandChartCanvas.Children.Add(failedBar);
        }

        BuildCommandXAxis(CommandXAxisGrid, bins);
    }

    private void RenderLastCommandPanel()
    {
        var last = _vm.LastCommand;

        LastCommandNameText.Text = last.Command;
        LastCommandIdText.Text = last.CommandId;
        LastCommandPriorityText.Text = last.Priority;
        LastCommandStatusText.Text = last.StatusLabel;
        LastCommandStartedText.Text = last.StartedAt;
        LastCommandCompletedText.Text = last.CompletedAt;
        LastCommandDurationText.Text = last.DurationText;
        LastCommandResultText.Text = last.ResultLine;
        LastCommandTransportText.Text = last.TransportLabel;
        LastCommandWorkerText.Text = last.TransportWorker;

        ApplyStatusBadge(
            LastCommandStatusBadge,
            LastCommandStatusText,
            last.StatusTone);

        var resultTone = BrushOf(ToneToBrushKey(last.StatusTone));
        LastCommandResultText.Foreground = resultTone;
        LastCommandResultIcon.Foreground = resultTone;
    }

    private void RenderFeed()
    {
        var items = _vm.WssFeedItems;
        if (items.Count == 0)
        {
            WssFeedSubtitleText.Text = "No feed messages yet";
        }
        else
        {
            var minSeq = items.Min(x => x.Sequence);
            var maxSeq = items.Max(x => x.Sequence);
            WssFeedSubtitleText.Text = $"Last {items.Count} messages - seq {minSeq}-{maxSeq}";
        }

        WssFeedItemsPanel.Children.Clear();
        foreach (var item in items)
        {
            WssFeedItemsPanel.Children.Add(CreateFeedRow(item));
        }
    }

    private FrameworkElement CreateFeedRow(DashboardFeedItem item)
    {
        var row = new Grid
        {
            Padding = new Thickness(20, 13, 20, 13),
            ColumnSpacing = 12,
            Background = item.Highlight ? BrushOf("SurfaceAltBrush") : new SolidColorBrush(Microsoft.UI.Colors.Transparent)
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var iconHost = new Border
        {
            Width = 36,
            Height = 36,
            CornerRadius = new CornerRadius(7),
            Background = ToneBackground(item.Tone),
            Child = new FontIcon
            {
                Glyph = item.Glyph,
                FontSize = 15,
                Foreground = BrushOf(ToneToBrushKey(item.Tone)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
        row.Children.Add(iconHost);

        var content = new StackPanel
        {
            Spacing = 5
        };
        Grid.SetColumn(content, 1);

        var titleRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 9
        };

        var typeText = new TextBlock
        {
            Text = FeedTypeLabel(item.Type),
            Foreground = BrushOf(ToneToBrushKey(item.Tone)),
            FontFamily = new FontFamily("Consolas"),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontSize = 13
        };
        var seqText = new TextBlock
        {
            Text = $"seq={item.Sequence}",
            Style = Resource("DashboardSubheadingStyle")
        };
        var dot = new Ellipse
        {
            Width = 9,
            Height = 9,
            Fill = BrushOf(ToneToBrushKey(item.DotTone)),
            Margin = new Thickness(0, 4, 0, 0)
        };

        titleRow.Children.Add(typeText);
        titleRow.Children.Add(seqText);
        titleRow.Children.Add(dot);
        content.Children.Add(titleRow);

        content.Children.Add(new TextBlock
        {
            Text = item.Summary,
            Foreground = BrushOf("TextSecondaryBrush"),
            FontFamily = new FontFamily("Consolas"),
            FontSize = 15,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 1
        });

        row.Children.Add(content);

        var right = new StackPanel
        {
            Spacing = 4,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        Grid.SetColumn(right, 2);
        right.Children.Add(new TextBlock
        {
            Text = item.Timestamp.ToLocalTime().ToString("HH:mm:ss"),
            Style = Resource("DashboardSubheadingStyle"),
            HorizontalAlignment = HorizontalAlignment.Right
        });
        right.Children.Add(new TextBlock
        {
            Text = item.Signature,
            Foreground = BrushOf("SuccessBrush"),
            FontFamily = new FontFamily("Consolas"),
            FontSize = 15,
            HorizontalAlignment = HorizontalAlignment.Right
        });
        row.Children.Add(right);

        return new StackPanel
        {
            Spacing = 0,
            Children =
            {
                row,
                new Border { Height = 1, Background = BrushOf("BorderBrush") }
            }
        };
    }

    private void ApplyCard(MetricCard card, DashboardMetricCardModel model)
    {
        card.Title = model.Title;
        card.Value = model.Value;
        card.Subtitle = model.Subtitle;
        card.Tone = model.Tone;
        card.Glyph = model.Glyph;
        card.DeltaText = model.DeltaText;
        card.DeltaTone = model.DeltaTone;
        card.BadgeText = model.BadgeText;
        card.BadgeTone = model.BadgeTone;
        card.StatusText = model.StatusText;
        card.StatusTone = model.StatusTone;
        card.ValueFontSize = model.ValueFontSize;
    }

    private void ApplySegmentButtonVisual(Button button, bool selected)
    {
        button.Foreground = selected ? BrushOf("TextPrimaryBrush") : BrushOf("TextMutedBrush");
        button.Background = selected ? BrushOf("SurfaceBrush") : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        button.Opacity = selected ? 1 : 0.9;
    }

    private void ApplyStatusBadge(Border host, TextBlock text, string tone)
    {
        host.Background = ToneBackground(tone);
        text.Foreground = BrushOf(ToneToBrushKey(tone));
    }

    private void DrawLineSeries(Canvas canvas, IReadOnlyList<double> values, double width, double usableHeight, double topPadding, double min, double max, Brush stroke)
    {
        if (values.Count < 2)
        {
            return;
        }

        var polyline = new Polyline
        {
            Stroke = stroke,
            StrokeThickness = 2.0
        };

        var leftPadding = 12.0;
        var plotWidth = width - leftPadding * 2;
        for (var i = 0; i < values.Count; i++)
        {
            var x = leftPadding + (plotWidth * i / (values.Count - 1));
            var norm = (values[i] - min) / (max - min);
            var y = topPadding + (usableHeight * (1 - norm));
            polyline.Points.Add(new Windows.Foundation.Point(x, y));
        }

        canvas.Children.Add(polyline);
    }

    private void DrawGridLines(Canvas canvas, double width, double height, int count)
    {
        for (var i = 0; i <= count; i++)
        {
            var y = 10 + ((height - 24) * i / count);
            var line = new Line
            {
                X1 = 10,
                X2 = width - 10,
                Y1 = y,
                Y2 = y,
                Stroke = BrushOf("BorderBrush"),
                StrokeDashArray = new DoubleCollection { 2, 6 },
                Opacity = 0.55
            };
            canvas.Children.Add(line);
        }
    }

    private void BuildXAxis(Grid axisGrid, IReadOnlyList<TelemetrySeriesPoint> points, int labelCount)
    {
        axisGrid.Children.Clear();
        axisGrid.ColumnDefinitions.Clear();
        if (labelCount <= 1)
        {
            return;
        }

        var step = Math.Max(1, points.Count / labelCount);
        var labels = points.Where((_, i) => i % step == 0).Take(labelCount).ToList();
        if (labels.Count == 0)
        {
            return;
        }

        for (var i = 0; i < labels.Count; i++)
        {
            axisGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var tb = new TextBlock
            {
                Text = labels[i].Timestamp.ToLocalTime().ToString("HH:mm"),
                Style = Resource("DashboardSubheadingStyle"),
                HorizontalAlignment = i == 0 ? HorizontalAlignment.Left : i == labels.Count - 1 ? HorizontalAlignment.Right : HorizontalAlignment.Center
            };
            Grid.SetColumn(tb, i);
            axisGrid.Children.Add(tb);
        }
    }

    private void BuildCommandXAxis(Grid axisGrid, IReadOnlyList<CommandExecutionBin> bins)
    {
        axisGrid.Children.Clear();
        axisGrid.ColumnDefinitions.Clear();
        foreach (var bin in bins)
        {
            axisGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var tb = new TextBlock
            {
                Text = bin.Hour.ToString("HH:mm"),
                Style = Resource("DashboardSubheadingStyle"),
                HorizontalAlignment = HorizontalAlignment.Center
            };
            Grid.SetColumn(tb, axisGrid.ColumnDefinitions.Count - 1);
            axisGrid.Children.Add(tb);
        }
    }

    private static string FeedTypeLabel(DashboardFeedType type)
    {
        return type switch
        {
            DashboardFeedType.Heartbeat => "HEARTBEAT",
            DashboardFeedType.Telemetry => "TELEMETRY",
            DashboardFeedType.KernelEvent => "KERNEL_EVENT",
            DashboardFeedType.CommandResult => "COMMAND_RESULT",
            _ => "COMMAND_DELIVERY"
        };
    }

    private static string ToneToBrushKey(string tone)
    {
        return (tone ?? string.Empty).ToLowerInvariant() switch
        {
            "success" => "SuccessBrush",
            "warning" => "WarningBrush",
            "danger" => "DangerBrush",
            "info" => "InfoBrush",
            _ => "TextSecondaryBrush"
        };
    }

    private Brush ToneBackground(string tone)
    {
        return (tone ?? string.Empty).ToLowerInvariant() switch
        {
            "success" => BrushOf("ChipSuccessBackgroundBrush"),
            "warning" => BrushOf("ChipWarningBackgroundBrush"),
            "danger" => BrushOf("ChipDangerBackgroundBrush"),
            "info" => BrushOf("ChipInfoBackgroundBrush"),
            _ => BrushOf("ChipNeutralBackgroundBrush")
        };
    }

    private Brush BrushOf(string key)
    {
        if (Resources.TryGetValue(key, out var localObj) && localObj is Brush localBrush)
        {
            return localBrush;
        }

        if (Application.Current.Resources.TryGetValue(key, out var appObj) && appObj is Brush appBrush)
        {
            return appBrush;
        }

        return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    private Style Resource(string key)
    {
        if (Resources.TryGetValue(key, out var localObj) && localObj is Style localStyle)
        {
            return localStyle;
        }

        if (Application.Current.Resources.TryGetValue(key, out var appObj) && appObj is Style appStyle)
        {
            return appStyle;
        }

        return new Style(typeof(TextBlock));
    }

    private void OnSyncNow(object sender, RoutedEventArgs e)
    {
        if (_vm.SyncNowCommand.CanExecute(null))
        {
            _vm.SyncNowCommand.Execute(null);
        }
    }

    private void OnSelectCpuRam(object sender, RoutedEventArgs e)
    {
        if (_vm.ShowCpuRamCommand.CanExecute(null))
        {
            _vm.ShowCpuRamCommand.Execute(null);
        }
    }

    private void OnSelectNetwork(object sender, RoutedEventArgs e)
    {
        if (_vm.ShowNetworkCommand.CanExecute(null))
        {
            _vm.ShowNetworkCommand.Execute(null);
        }
    }

    private void OnOpenFullLog(object sender, RoutedEventArgs e)
    {
        Frame?.Navigate(typeof(ActivityDiagnosticsPage));
    }

    private void OnTelemetryChartCanvasSizeChanged(object sender, SizeChangedEventArgs e)
    {
        RenderTelemetryChart();
    }

    private void OnCommandChartCanvasSizeChanged(object sender, SizeChangedEventArgs e)
    {
        RenderCommandChart();
    }

    private void OnPageUnloaded(object sender, RoutedEventArgs e)
    {
        Unloaded -= OnPageUnloaded;
        _vm.PropertyChanged -= HandleViewModelPropertyChanged;
        _vm.Dispose();
    }
}
