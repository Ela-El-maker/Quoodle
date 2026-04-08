using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class QuickStatusPage : Page
{
    private readonly QuickStatusViewModel _vm;

    public QuickStatusPage()
    {
        InitializeComponent();
        _vm = new QuickStatusViewModel(App.StateStore);
        _vm.PropertyChanged += (_, _) => Render();
        Render();
    }

    private void Render()
    {
        ConnectionChip.Label = _vm.Connection;
        ConnectionChip.Tone = ResolveConnectionTone(_vm.Connection);

        DeviceNameText.Text = _vm.DeviceName;
        DeviceIdText.Text = _vm.DeviceId;
        AgentVersionText.Text = _vm.AgentVersion;
        LatencyHeaderText.Text = $"{_vm.LatencyMs} ms";
        PolicyHashText.Text = $"sha256:{Math.Abs(_vm.DeviceId.GetHashCode()):x8}";

        HealthChip.Label = _vm.Health;
        HealthChip.Tone = _vm.Health switch
        {
            "Healthy" => "Success",
            "Warning" => "Warning",
            "Critical" => "Danger",
            _ => "Neutral"
        };

        LastSyncCard.Title = "Last Sync";
        LastSyncCard.Value = _vm.LastSync;
        LastSyncCard.Subtitle = "Auto-sync every 30s";
        LastSyncCard.Tone = "Info";

        CpuCard.Title = "CPU Usage";
        CpuCard.Value = $"{_vm.CpuPercent:0.0}%";
        CpuCard.Subtitle = "Agent process only";
        CpuCard.Tone = _vm.Connection == "Connected" ? "Success" : "Info";

        MemoryCard.Title = "Memory";
        MemoryCard.Value = $"{Math.Max(12, _vm.MemoryPercent) * 1.1:0.0} MB";
        MemoryCard.Subtitle = "Resident set size";
        MemoryCard.Tone = "Info";

        EventsCard.Title = "Pending Events";
        EventsCard.Value = _vm.PendingEvents.ToString();
        EventsCard.Subtitle = "Awaiting flush";
        EventsCard.Tone = _vm.PendingEvents > 0 ? "Warning" : "Success";

        ActivityText.Text = _vm.Activity;
        HeartbeatText.Text = $"Last heartbeat {_vm.LastHeartbeat}";
        ReconnectText.Text = _vm.ReconnectAttempts == 0
            ? "Stable transport path"
            : $"Reconnect attempts {_vm.ReconnectAttempts}";

        WarningTitleText.Text = _vm.PendingEvents > 0
            ? $"{_vm.PendingEvents} kernel events pending review"
            : "No queued events";
        SyncText.Text = _vm.PendingEvents > 0
            ? "Events are queued for flush. Trigger a sync or inspect diagnostics."
            : "Transport is healthy and the mock queue is clear.";
    }

    private static string ResolveConnectionTone(string connection)
    {
        return connection switch
        {
            "Connected" => "Success",
            "Reconnecting" => "Warning",
            "Offline" => "Danger",
            "AuthFailed" => "Danger",
            _ => "Info"
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
}
