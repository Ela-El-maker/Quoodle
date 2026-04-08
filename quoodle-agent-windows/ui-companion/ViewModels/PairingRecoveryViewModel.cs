using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class PairingRecoveryViewModel : ObservableObject
{
    private readonly AgentStateStore _store;

    private bool _isPaired;
    private string _deviceName = string.Empty;
    private string _deviceId = string.Empty;
    private string _connection = string.Empty;
    private string _health = string.Empty;
    private string _currentActivity = string.Empty;
    private string _latestFailureContext = "No recent failures.";

    public PairingRecoveryViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += (_, snapshot) => Apply(snapshot);

        RetryConnectionCommand = new RelayCommand(() => _store.RetryConnection());
        StartRePairCommand = new RelayCommand(() => _store.BeginRePairFlow());
        ResetUiSessionCommand = new RelayCommand(() => _store.ResetUiSession());

        Apply(_store.Snapshot);
    }

    public RelayCommand RetryConnectionCommand { get; }

    public RelayCommand StartRePairCommand { get; }

    public RelayCommand ResetUiSessionCommand { get; }

    public bool IsPaired
    {
        get => _isPaired;
        private set => SetProperty(ref _isPaired, value);
    }

    public string DeviceName
    {
        get => _deviceName;
        private set => SetProperty(ref _deviceName, value);
    }

    public string DeviceId
    {
        get => _deviceId;
        private set => SetProperty(ref _deviceId, value);
    }

    public string Connection
    {
        get => _connection;
        private set => SetProperty(ref _connection, value);
    }

    public string Health
    {
        get => _health;
        private set => SetProperty(ref _health, value);
    }

    public string CurrentActivity
    {
        get => _currentActivity;
        private set => SetProperty(ref _currentActivity, value);
    }

    public string LatestFailureContext
    {
        get => _latestFailureContext;
        private set => SetProperty(ref _latestFailureContext, value);
    }

    private void Apply(AgentStateSnapshot snapshot)
    {
        IsPaired = snapshot.IsPaired;
        DeviceName = snapshot.DeviceName;
        DeviceId = snapshot.DeviceId;
        Connection = snapshot.Connection.ToString();
        Health = snapshot.Health.ToString();
        CurrentActivity = snapshot.CurrentActivity;
        LatestFailureContext = ResolveFailureContext(snapshot);
    }

    private static string ResolveFailureContext(AgentStateSnapshot snapshot)
    {
        var cmdFailure = snapshot.CommandHistory.FirstOrDefault(x =>
            x.Status is CommandExecutionStatus.Failed or CommandExecutionStatus.TimedOut or CommandExecutionStatus.Rejected);
        if (cmdFailure is not null)
        {
            var msg = string.IsNullOrWhiteSpace(cmdFailure.ErrorMessage)
                ? cmdFailure.Status.ToString()
                : cmdFailure.ErrorMessage;
            return $"{cmdFailure.Command} ({cmdFailure.Source}): {msg}";
        }

        var activityFailure = snapshot.Activity.FirstOrDefault(x => x.Severity is ActivitySeverity.Error or ActivitySeverity.Warning);
        if (activityFailure is not null)
        {
            return $"{activityFailure.Title}: {activityFailure.Details}";
        }

        return "No recent failures.";
    }
}
