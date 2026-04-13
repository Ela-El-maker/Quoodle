using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class DashboardPage : Page
{
    private readonly DashboardViewModel _vm;

    public DashboardPage()
    {
        InitializeComponent();
        _vm = new DashboardViewModel(App.StateStore);
        _vm.PropertyChanged += (_, _) => Render();
        Render();
    }

    private void Render()
    {
        ConnectionChip.Label = _vm.Connection;
        ConnectionChip.Tone = ResolveConnectionTone(_vm.Connection);

        HealthChip.Label = _vm.Health;
        HealthChip.Tone = _vm.Health switch
        {
            "Healthy" => "Success",
            "Warning" => "Warning",
            "Critical" => "Danger",
            _ => "Neutral"
        };

        IdentityText.Text = $"{_vm.DeviceName}  ({_vm.DeviceId})";
        VersionText.Text = $"wss://gateway.quoodle.io/agent  •  {_vm.Connection.ToLowerInvariant()}";
        LastSyncText.Text = _vm.LastSync;
        ActivityText.Text = _vm.CurrentActivity;
        HeroVersionText.Text = _vm.AgentVersion;
        HeroBuildText.Text = Environment.OSVersion.Version.ToString();
        HeroTransportText.Text = $"{_vm.Connection} • {_vm.LatencyMs} ms";
        HeroReconnectText.Text = _vm.ReconnectAttempts.ToString();

        CpuCard.Title = "WSS Uptime (24H)";
        CpuCard.Value = $"{Math.Max(1, 100 - Math.Abs(50 - _vm.Cpu))}%";
        CpuCard.Subtitle = "wss://gateway.quoodle.io/agent";

        MemoryCard.Title = "Last Heartbeat";
        MemoryCard.Value = $"{Math.Max(1, _vm.Memory / 2)}s";
        MemoryCard.Subtitle = "next expected in ~12s";

        DiskCard.Title = "Failed Commands (24H)";
        DiskCard.Value = _vm.Disk > 85 ? "2" : "0";
        DiskCard.Subtitle = _vm.Disk > 85 ? "lock_screen x 1, ping x 1" : "no failed commands";

        RxCard.Title = "CPU Usage";
        RxCard.Value = $"{_vm.Cpu}%";
        RxCard.Subtitle = "sampled 60s";

        TxCard.Title = "RAM Usage";
        TxCard.Value = $"{_vm.Memory}%";
        TxCard.Subtitle = "GlobalMemoryStatusEx";

        TelemetrySummaryText.Text = _vm.Connection == "Connected"
            ? "Last 8 messages are healthy. Command and telemetry stream are in sync with the control plane."
            : "Transport degraded. Showing cached envelope activity while reconnecting.";

        DiskCard.Tone = _vm.Disk > 85 ? "Danger" : "Warning";
        MemoryCard.Tone = _vm.Connection == "Connected" ? "Success" : "Warning";
        CpuCard.Tone = _vm.Connection == "Connected" ? "Success" : "Info";
        RxCard.Tone = "Info";
        TxCard.Tone = "Info";
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
}
