using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class SettingsViewModel : ObservableObject
{
    private readonly AgentStateStore _store;
    private bool _suppressUpdates;

    private bool _notifyInfo;
    private bool _notifyWarningsAndCritical;
    private bool _backgroundSync;
    private bool _collectDiagnostics;
    private bool _startWithWindows;
    private bool _allowTrayNotifications;

    private string _deviceId = string.Empty;
    private string _deviceName = string.Empty;

    public SettingsViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += (_, s) => Apply(s);
        SyncNowCommand = new RelayCommand(() => _store.TriggerSyncNow());
        Apply(_store.Snapshot);
    }

    public RelayCommand SyncNowCommand { get; }

    public string DeviceId { get => _deviceId; private set => SetProperty(ref _deviceId, value); }
    public string DeviceName { get => _deviceName; private set => SetProperty(ref _deviceName, value); }

    public bool NotifyInfo
    {
        get => _notifyInfo;
        set { if (SetProperty(ref _notifyInfo, value)) Commit(); }
    }

    public bool NotifyWarningsAndCritical
    {
        get => _notifyWarningsAndCritical;
        set { if (SetProperty(ref _notifyWarningsAndCritical, value)) Commit(); }
    }

    public bool BackgroundSync
    {
        get => _backgroundSync;
        set { if (SetProperty(ref _backgroundSync, value)) Commit(); }
    }

    public bool CollectDiagnostics
    {
        get => _collectDiagnostics;
        set { if (SetProperty(ref _collectDiagnostics, value)) Commit(); }
    }

    public bool StartWithWindows
    {
        get => _startWithWindows;
        set { if (SetProperty(ref _startWithWindows, value)) Commit(); }
    }

    public bool AllowTrayNotifications
    {
        get => _allowTrayNotifications;
        set { if (SetProperty(ref _allowTrayNotifications, value)) Commit(); }
    }

    private void Apply(AgentStateSnapshot snapshot)
    {
        _suppressUpdates = true;
        DeviceId = snapshot.DeviceId;
        DeviceName = snapshot.DeviceName;

        NotifyInfo = snapshot.Settings.NotifyInfo;
        NotifyWarningsAndCritical = snapshot.Settings.NotifyWarningsAndCritical;
        BackgroundSync = snapshot.Settings.BackgroundSync;
        CollectDiagnostics = snapshot.Settings.CollectDiagnostics;
        StartWithWindows = snapshot.Settings.StartWithWindows;
        AllowTrayNotifications = snapshot.Settings.AllowTrayNotifications;
        _suppressUpdates = false;
    }

    private void Commit()
    {
        if (_suppressUpdates)
        {
            return;
        }

        _store.UpdateSettings(new UiSettings(
            NotifyInfo,
            NotifyWarningsAndCritical,
            BackgroundSync,
            CollectDiagnostics,
            StartWithWindows,
            AllowTrayNotifications));
    }
}
