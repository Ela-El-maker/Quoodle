using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class DeviceDetailsPage : Page
{
    private readonly DeviceDetailsViewModel _vm;

    public DeviceDetailsPage()
    {
        InitializeComponent();
        _vm = new DeviceDetailsViewModel(App.StateStore);
        _vm.PropertyChanged += (_, _) => Render();

        IdentityFactsList.ItemsSource = _vm.IdentityFacts;
        RuntimeFactsList.ItemsSource = _vm.RuntimeFacts;
        NetworkFactsList.ItemsSource = _vm.NetworkFacts;
        SyncFactsList.ItemsSource = _vm.SyncFacts;

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

        SummaryText.Text = $"{_vm.DeviceName} ({_vm.DeviceId}) - Last sync {_vm.LastSync}";
        HeroDeviceText.Text = $"{_vm.DeviceName} / {_vm.DeviceId}";
        HeroStatusText.Text = $"Connection {_vm.Connection} - Health {_vm.Health}";

        ConnectionCard.Title = "Transport";
        ConnectionCard.Value = _vm.Connection;
        ConnectionCard.Subtitle = "Driver + agent channel";
        ConnectionCard.Tone = ResolveConnectionTone(_vm.Connection);

        HealthCard.Title = "Health";
        HealthCard.Value = _vm.Health;
        HealthCard.Subtitle = "Mock telemetry posture";
        HealthCard.Tone = _vm.Health switch
        {
            "Healthy" => "Success",
            "Warning" => "Warning",
            "Critical" => "Danger",
            _ => "Info"
        };

        SyncCard.Title = "Last Sync";
        SyncCard.Value = _vm.LastSync.Split(' ').LastOrDefault() ?? _vm.LastSync;
        SyncCard.Subtitle = _vm.LastSync;
        SyncCard.Tone = "Info";
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
}
