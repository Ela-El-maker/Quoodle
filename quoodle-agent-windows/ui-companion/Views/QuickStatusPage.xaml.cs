using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.ComponentModel;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class QuickStatusPage : Page
{
    private readonly QuickStatusViewModel _vm;

    public QuickStatusPage()
    {
        InitializeComponent();
        _vm = new QuickStatusViewModel(App.StateStore);
        _vm.PropertyChanged += HandleViewModelPropertyChanged;
        Unloaded += OnPageUnloaded;
        Render();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
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
        ConnectionPillText.Text = _vm.Connection;
        var toneBrush = BrushOf(ToneToBrushKey(_vm.ConnectionTone));
        ConnectionPillDot.Fill = toneBrush;
        ConnectionPillIcon.Foreground = toneBrush;
        ConnectionPillText.Foreground = toneBrush;
        ConnectionPill.BorderBrush = toneBrush;
        ConnectionPill.Background = ToneToBackground(_vm.ConnectionTone);

        DeviceNameText.Text = _vm.DeviceName;
        DeviceIdText.Text = _vm.DeviceId;
        AgentVersionText.Text = _vm.AgentVersion;
        UptimeText.Text = _vm.UptimeLabel;
        PolicyHashText.Text = _vm.PolicyHash;

        LastSyncCard.Title = "Last Sync";
        LastSyncCard.Value = _vm.LastSyncAge;
        LastSyncCard.Subtitle = "Auto-sync every 30s";
        LastSyncCard.Tone = "Info";

        CpuCard.Title = "CPU Usage";
        CpuCard.Value = _vm.CpuUsageLabel;
        CpuCard.Subtitle = "Agent process only";
        CpuCard.Tone = _vm.ConnectionTone == "Success" ? "Success" : "Info";

        MemoryCard.Title = "Memory";
        MemoryCard.Value = _vm.MemoryMbLabel;
        MemoryCard.Subtitle = "Resident set size";
        MemoryCard.Tone = "Info";

        EventsCard.Title = "Pending Events";
        EventsCard.Value = _vm.PendingEvents.ToString();
        EventsCard.Subtitle = "Awaiting flush";
        EventsCard.BadgeText = _vm.HasPendingEvents ? _vm.PendingEvents.ToString() : string.Empty;
        EventsCard.BadgeTone = _vm.HasPendingEvents ? "Warning" : "Neutral";
        EventsCard.Tone = _vm.HasPendingEvents ? "Warning" : "Success";

        ActivityText.Text = _vm.ActivityTitle;
        ActivityDetailsText.Text = $"{_vm.ActivityDetails} - last heartbeat {_vm.LastHeartbeatAge}";

        WarningTitleText.Text = _vm.WarningTitle;
        WarningDetailsText.Text = _vm.WarningDetails;
        WarningReviewText.Text = _vm.HasPendingEvents ? "Review ->" : "Healthy";

        WarningPanel.Background = _vm.HasPendingEvents
            ? BrushOf("WarningPanelBackgroundBrush")
            : BrushOf("SurfaceAltBrush");
        WarningPanel.BorderBrush = _vm.HasPendingEvents
            ? BrushOf("WarningPanelBorderBrush")
            : BrushOf("BorderBrush");

        var warningTextBrush = _vm.HasPendingEvents
            ? BrushOf("ChipWarningForegroundBrush")
            : BrushOf("TextSecondaryBrush");
        WarningTitleText.Foreground = warningTextBrush;
        WarningDetailsText.Foreground = warningTextBrush;
        WarningReviewText.Foreground = warningTextBrush;
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

    private Brush ToneToBackground(string tone)
    {
        return tone switch
        {
            "Success" => BrushOf("ChipSuccessBackgroundBrush"),
            "Warning" => BrushOf("ChipWarningBackgroundBrush"),
            "Danger" => BrushOf("ChipDangerBackgroundBrush"),
            "Info" => BrushOf("ChipInfoBackgroundBrush"),
            _ => BrushOf("SurfaceAltBrush")
        };
    }

    private static string ToneToBrushKey(string tone)
    {
        return tone switch
        {
            "Success" => "SuccessBrush",
            "Warning" => "WarningBrush",
            "Danger" => "DangerBrush",
            "Info" => "InfoBrush",
            _ => "TextSecondaryBrush"
        };
    }

    private void OnSyncNow(object sender, RoutedEventArgs e)
    {
        if (_vm.SyncNowCommand.CanExecute(null))
        {
            _vm.SyncNowCommand.Execute(null);
        }
    }

    private void OnOpenDashboard(object sender, RoutedEventArgs e)
    {
        Frame?.Navigate(typeof(DashboardPage));
    }

    private void OnViewLogs(object sender, RoutedEventArgs e)
    {
        Frame?.Navigate(typeof(ActivityDiagnosticsPage));
    }

    private void OnPageUnloaded(object sender, RoutedEventArgs e)
    {
        Unloaded -= OnPageUnloaded;
        _vm.PropertyChanged -= HandleViewModelPropertyChanged;
        _vm.Dispose();
    }
}
