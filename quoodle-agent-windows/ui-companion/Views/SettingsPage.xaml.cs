using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.ViewModels;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class SettingsPage : Page
{
    private readonly SettingsViewModel _vm;
    private bool _updating;

    public SettingsPage()
    {
        InitializeComponent();
        _vm = new SettingsViewModel(App.StateStore);
        _vm.PropertyChanged += (_, _) => Render();
        Render();
    }

    private void Render()
    {
        _updating = true;
        IdentityText.Text = $"Device: {_vm.DeviceName} ({_vm.DeviceId})";
        NotifyInfoSwitch.IsOn = _vm.NotifyInfo;
        NotifyCriticalSwitch.IsOn = _vm.NotifyWarningsAndCritical;
        BackgroundSyncSwitch.IsOn = _vm.BackgroundSync;
        DiagnosticsSwitch.IsOn = _vm.CollectDiagnostics;
        StartupSwitch.IsOn = _vm.StartWithWindows;
        TraySwitch.IsOn = _vm.AllowTrayNotifications;
        _updating = false;
    }

    private void OnToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_updating)
        {
            return;
        }

        _vm.NotifyInfo = NotifyInfoSwitch.IsOn;
        _vm.NotifyWarningsAndCritical = NotifyCriticalSwitch.IsOn;
        _vm.BackgroundSync = BackgroundSyncSwitch.IsOn;
        _vm.CollectDiagnostics = DiagnosticsSwitch.IsOn;
        _vm.StartWithWindows = StartupSwitch.IsOn;
        _vm.AllowTrayNotifications = TraySwitch.IsOn;
    }

    private void OnSyncNow(object sender, RoutedEventArgs e)
    {
        if (_vm.SyncNowCommand.CanExecute(null))
        {
            _vm.SyncNowCommand.Execute(null);
        }
    }
}
