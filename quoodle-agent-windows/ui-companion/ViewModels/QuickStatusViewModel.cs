using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using System.Linq;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class QuickStatusViewModel : ObservableObject, IDisposable
{
    private readonly AgentStateStore _store;

    private string _deviceName = string.Empty;
    private string _deviceId = string.Empty;
    private string _agentVersion = string.Empty;
    private string _policyHash = "sha256:pending";
    private string _connection = "Connecting";
    private string _connectionTone = "Info";
    private string _lastHeartbeatAge = "--";
    private string _lastSyncAge = "--";
    private string _activityTitle = "Idle";
    private string _activityDetails = "Waiting for activity samples.";
    private string _uptimeLabel = "--";
    private int _reconnectAttempts;
    private int _cpuPercent;
    private int _memoryPercent;
    private int _pendingEvents;
    private string _warningTitle = "No kernel events pending review";
    private string _warningDetails = "Transport is healthy and there are no queued events.";

    public QuickStatusViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += HandleSnapshotChanged;
        SyncNowCommand = new RelayCommand(() => _store.TriggerSyncNow());
        Apply(_store.Snapshot);
    }

    public RelayCommand SyncNowCommand { get; }

    public string DeviceName { get => _deviceName; private set => SetProperty(ref _deviceName, value); }
    public string DeviceId { get => _deviceId; private set => SetProperty(ref _deviceId, value); }
    public string AgentVersion { get => _agentVersion; private set => SetProperty(ref _agentVersion, value); }
    public string PolicyHash { get => _policyHash; private set => SetProperty(ref _policyHash, value); }
    public string Connection { get => _connection; private set => SetProperty(ref _connection, value); }
    public string ConnectionTone { get => _connectionTone; private set => SetProperty(ref _connectionTone, value); }
    public string LastHeartbeatAge { get => _lastHeartbeatAge; private set => SetProperty(ref _lastHeartbeatAge, value); }
    public string LastSyncAge { get => _lastSyncAge; private set => SetProperty(ref _lastSyncAge, value); }
    public string ActivityTitle { get => _activityTitle; private set => SetProperty(ref _activityTitle, value); }
    public string ActivityDetails { get => _activityDetails; private set => SetProperty(ref _activityDetails, value); }
    public string UptimeLabel { get => _uptimeLabel; private set => SetProperty(ref _uptimeLabel, value); }
    public int ReconnectAttempts { get => _reconnectAttempts; private set => SetProperty(ref _reconnectAttempts, value); }
    public int CpuPercent { get => _cpuPercent; private set => SetProperty(ref _cpuPercent, value); }
    public int MemoryPercent { get => _memoryPercent; private set => SetProperty(ref _memoryPercent, value); }
    public int PendingEvents { get => _pendingEvents; private set => SetProperty(ref _pendingEvents, value); }
    public string WarningTitle { get => _warningTitle; private set => SetProperty(ref _warningTitle, value); }
    public string WarningDetails { get => _warningDetails; private set => SetProperty(ref _warningDetails, value); }

    public string CpuUsageLabel => $"{CpuPercent / 5.0:0.0}%";

    public string MemoryMbLabel => $"{Math.Max(12, MemoryPercent) * 1.1:0.0} MB";

    public bool HasPendingEvents => PendingEvents > 0;

    private void Apply(AgentStateSnapshot snapshot)
    {
        var now = DateTimeOffset.UtcNow;

        DeviceName = snapshot.DeviceName;
        DeviceId = snapshot.DeviceId;
        AgentVersion = snapshot.AgentVersion;
        PolicyHash = string.IsNullOrWhiteSpace(snapshot.PolicyHash) ? "sha256:pending" : snapshot.PolicyHash;
        Connection = snapshot.Connection.ToString();
        ConnectionTone = ResolveConnectionTone(snapshot.Connection);
        LastHeartbeatAge = FormatAge(snapshot.LastHeartbeatUtc, now);
        LastSyncAge = FormatAge(snapshot.LastSyncUtc, now);
        ActivityTitle = BuildActivityTitle(snapshot);
        ActivityDetails = BuildActivityDetails(snapshot);
        ReconnectAttempts = snapshot.ReconnectAttempts;
        UptimeLabel = ReconnectAttempts == 0 ? "24h 0m" : $"{ReconnectAttempts} reconnects";
        CpuPercent = snapshot.CpuPercent;
        MemoryPercent = snapshot.MemoryPercent;
        PendingEvents = snapshot.CommandHistory.Count(x => x.Status is CommandExecutionStatus.Queued or CommandExecutionStatus.Dispatched or CommandExecutionStatus.Executing);

        WarningTitle = PendingEvents > 0
            ? $"{PendingEvents} kernel events pending review"
            : "No kernel events pending review";
        WarningDetails = PendingEvents > 0
            ? "Events are queued for flush. Trigger a sync or check the diagnostics log."
            : "No active queue pressure detected on the transport path.";

        RaisePropertyChanged(nameof(CpuUsageLabel));
        RaisePropertyChanged(nameof(MemoryMbLabel));
        RaisePropertyChanged(nameof(HasPendingEvents));
    }

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        Apply(snapshot);
    }

    private static string ResolveConnectionTone(ConnectionState state)
    {
        return state switch
        {
            ConnectionState.Connected => "Success",
            ConnectionState.Reconnecting => "Warning",
            ConnectionState.Offline => "Danger",
            ConnectionState.AuthFailed => "Danger",
            _ => "Info"
        };
    }

    private static string FormatAge(DateTimeOffset timestamp, DateTimeOffset now)
    {
        var age = now - timestamp;
        if (age.TotalSeconds < 60)
        {
            return $"{Math.Max(1, (int)age.TotalSeconds)}s ago";
        }

        if (age.TotalMinutes < 60)
        {
            return $"{(int)age.TotalMinutes}m ago";
        }

        return $"{(int)age.TotalHours}h ago";
    }

    private static string BuildActivityTitle(AgentStateSnapshot snapshot)
    {
        var latest = snapshot.Activity.OrderByDescending(x => x.Timestamp).FirstOrDefault();
        if (latest is null)
        {
            return string.IsNullOrWhiteSpace(snapshot.CurrentActivity) ? "Idle" : snapshot.CurrentActivity;
        }

        if (!string.IsNullOrWhiteSpace(latest.Title))
        {
            return latest.Title;
        }

        return string.IsNullOrWhiteSpace(snapshot.CurrentActivity) ? "Idle" : snapshot.CurrentActivity;
    }

    private static string BuildActivityDetails(AgentStateSnapshot snapshot)
    {
        var latest = snapshot.Activity.OrderByDescending(x => x.Timestamp).FirstOrDefault();
        if (latest is null)
        {
            return "Waiting for fresh diagnostics samples.";
        }

        var details = string.IsNullOrWhiteSpace(latest.Details) ? "No details." : latest.Details;
        return $"{latest.Source} - {details}";
    }

    public void Dispose()
    {
        _store.SnapshotChanged -= HandleSnapshotChanged;
    }
}
