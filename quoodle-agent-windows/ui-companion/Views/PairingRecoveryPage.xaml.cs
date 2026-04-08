using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class PairingRecoveryPage : Page
{
    private readonly PairingRecoveryViewModel _vm;

    public PairingRecoveryPage()
    {
        InitializeComponent();
        _vm = new PairingRecoveryViewModel(App.StateStore);
        _vm.PropertyChanged += (_, _) => Render();
        Render();
    }

    private void Render()
    {
        PairStateChip.Label = _vm.IsPaired ? "Paired" : "Unpaired";
        PairStateChip.Tone = _vm.IsPaired ? "Success" : "Warning";

        ConnectionChip.Label = _vm.Connection;
        ConnectionChip.Tone = ResolveConnectionTone(_vm.Connection);

        IdentityText.Text = $"{_vm.DeviceName} ({_vm.DeviceId})";
        HealthText.Text = $"Health: {_vm.Health}";
        ActivityText.Text = $"Current activity: {_vm.CurrentActivity}";
        FailureContextText.Text = _vm.LatestFailureContext;
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

    private void OnRetryConnection(object sender, RoutedEventArgs e)
    {
        if (_vm.RetryConnectionCommand.CanExecute(null))
        {
            _vm.RetryConnectionCommand.Execute(null);
        }
    }

    private void OnRePair(object sender, RoutedEventArgs e)
    {
        if (_vm.StartRePairCommand.CanExecute(null))
        {
            _vm.StartRePairCommand.Execute(null);
        }
    }

    private void OnResetSession(object sender, RoutedEventArgs e)
    {
        if (_vm.ResetUiSessionCommand.CanExecute(null))
        {
            _vm.ResetUiSessionCommand.Execute(null);
        }
    }
}
