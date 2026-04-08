using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using System.Linq;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class QuickStatusViewModel : ObservableObject
{
    private readonly AgentStateStore _store;
    private string _deviceName = string.Empty;
    private string _deviceId = string.Empty;
    private string _agentVersion = string.Empty;
    private string _connection = string.Empty;
    private string _health = string.Empty;
    private string _lastHeartbeat = string.Empty;
    private string _lastSync = string.Empty;
    private string _activity = string.Empty;
    private int _latency;
    private int _reconnectAttempts;
    private int _cpuPercent;
    private int _memoryPercent;
    private int _pendingEvents;

    public QuickStatusViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += (_, s) => Apply(s);
        SyncNowCommand = new RelayCommand(() => _store.TriggerSyncNow());
        Apply(_store.Snapshot);
    }

    public RelayCommand SyncNowCommand { get; }

    public string DeviceName { get => _deviceName; private set => SetProperty(ref _deviceName, value); }
    public string DeviceId { get => _deviceId; private set => SetProperty(ref _deviceId, value); }
    public string AgentVersion { get => _agentVersion; private set => SetProperty(ref _agentVersion, value); }
    public string Connection { get => _connection; private set => SetProperty(ref _connection, value); }
    public string Health { get => _health; private set => SetProperty(ref _health, value); }
    public string LastHeartbeat { get => _lastHeartbeat; private set => SetProperty(ref _lastHeartbeat, value); }
    public string LastSync { get => _lastSync; private set => SetProperty(ref _lastSync, value); }
    public string Activity { get => _activity; private set => SetProperty(ref _activity, value); }
    public int LatencyMs { get => _latency; private set => SetProperty(ref _latency, value); }
    public int ReconnectAttempts { get => _reconnectAttempts; private set => SetProperty(ref _reconnectAttempts, value); }
    public int CpuPercent { get => _cpuPercent; private set => SetProperty(ref _cpuPercent, value); }
    public int MemoryPercent { get => _memoryPercent; private set => SetProperty(ref _memoryPercent, value); }
    public int PendingEvents { get => _pendingEvents; private set => SetProperty(ref _pendingEvents, value); }

    private void Apply(AgentStateSnapshot snapshot)
    {
        DeviceName = snapshot.DeviceName;
        DeviceId = snapshot.DeviceId;
        AgentVersion = snapshot.AgentVersion;
        Connection = snapshot.Connection.ToString();
        Health = snapshot.Health.ToString();
        LastHeartbeat = snapshot.LastHeartbeatUtc.LocalDateTime.ToString("HH:mm:ss");
        LastSync = snapshot.LastSyncUtc.LocalDateTime.ToString("HH:mm:ss");
        Activity = snapshot.CurrentActivity;
        LatencyMs = snapshot.LatencyMs;
        ReconnectAttempts = snapshot.ReconnectAttempts;
        CpuPercent = snapshot.CpuPercent;
        MemoryPercent = snapshot.MemoryPercent;
        PendingEvents = snapshot.CommandHistory.Count(x => x.Status is CommandExecutionStatus.Queued or CommandExecutionStatus.Dispatched or CommandExecutionStatus.Executing);
    }
}
