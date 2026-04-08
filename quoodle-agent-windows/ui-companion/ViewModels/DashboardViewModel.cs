using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class DashboardViewModel : ObservableObject
{
    private readonly AgentStateStore _store;

    private string _deviceName = string.Empty;
    private string _deviceId = string.Empty;
    private string _agentVersion = string.Empty;
    private string _connection = string.Empty;
    private string _health = string.Empty;
    private string _currentActivity = string.Empty;
    private string _lastSync = string.Empty;
    private int _reconnectAttempts;
    private int _latencyMs;

    private int _cpu;
    private int _memory;
    private int _disk;
    private double _rx;
    private double _tx;

    public DashboardViewModel(AgentStateStore store)
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
    public string CurrentActivity { get => _currentActivity; private set => SetProperty(ref _currentActivity, value); }
    public string LastSync { get => _lastSync; private set => SetProperty(ref _lastSync, value); }
    public int ReconnectAttempts { get => _reconnectAttempts; private set => SetProperty(ref _reconnectAttempts, value); }
    public int LatencyMs { get => _latencyMs; private set => SetProperty(ref _latencyMs, value); }

    public int Cpu { get => _cpu; private set => SetProperty(ref _cpu, value); }
    public int Memory { get => _memory; private set => SetProperty(ref _memory, value); }
    public int Disk { get => _disk; private set => SetProperty(ref _disk, value); }
    public double NetworkRx { get => _rx; private set => SetProperty(ref _rx, value); }
    public double NetworkTx { get => _tx; private set => SetProperty(ref _tx, value); }

    private void Apply(AgentStateSnapshot snapshot)
    {
        DeviceName = snapshot.DeviceName;
        DeviceId = snapshot.DeviceId;
        AgentVersion = snapshot.AgentVersion;
        Connection = snapshot.Connection.ToString();
        Health = snapshot.Health.ToString();
        CurrentActivity = snapshot.CurrentActivity;
        LastSync = snapshot.LastSyncUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss");
        ReconnectAttempts = snapshot.ReconnectAttempts;
        LatencyMs = snapshot.LatencyMs;
        Cpu = snapshot.CpuPercent;
        Memory = snapshot.MemoryPercent;
        Disk = snapshot.DiskPercent;
        NetworkRx = snapshot.NetworkRxMbps;
        NetworkTx = snapshot.NetworkTxMbps;
    }
}
