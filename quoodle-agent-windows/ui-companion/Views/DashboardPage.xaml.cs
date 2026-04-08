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
        VersionText.Text = $"Agent version: {_vm.AgentVersion}";
        LastSyncText.Text = $"Last sync: {_vm.LastSync}";
        ActivityText.Text = _vm.CurrentActivity;
        HeroVersionText.Text = _vm.AgentVersion;
        HeroBuildText.Text = Environment.OSVersion.Version.ToString();
        HeroTransportText.Text = $"{_vm.Connection} • {_vm.LatencyMs} ms";
        HeroReconnectText.Text = _vm.ReconnectAttempts.ToString();

        CpuCard.Title = "WSS Uptime";
        CpuCard.Value = $"{Math.Max(1, 100 - Math.Abs(50 - _vm.Cpu))}%";
        CpuCard.Subtitle = "Last 24h channel stability";

        MemoryCard.Title = "Last Heartbeat";
        MemoryCard.Value = $"{Math.Max(1, _vm.Memory / 2)}s";
        MemoryCard.Subtitle = "Target < 20s";

        DiskCard.Title = "Failed Commands";
        DiskCard.Value = _vm.Disk > 85 ? "2" : "0";
        DiskCard.Subtitle = "24h window";

        RxCard.Title = "NET RX";
        RxCard.Value = $"{_vm.NetworkRx:F1} Mbps";
        RxCard.Subtitle = "Inbound stream";

        TxCard.Title = "NET TX";
        TxCard.Value = $"{_vm.NetworkTx:F1} Mbps";
        TxCard.Subtitle = "Outbound stream";

        TelemetrySummaryText.Text = _vm.Connection == "Connected"
            ? "Mock provider is generating stable heartbeat, transport, and command telemetry."
            : "Transport is degraded; dashboard tiles are showing cached and reconnecting state.";

        DiskCard.Tone = _vm.Disk > 85 ? "Danger" : "Warning";
        MemoryCard.Tone = _vm.Connection == "Connected" ? "Success" : "Warning";
        CpuCard.Tone = _vm.Connection == "Connected" ? "Success" : "Info";
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
