using System.Collections.ObjectModel;
using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class DeviceDetailsViewModel : ObservableObject
{
    private readonly AgentStateStore _store;

    private string _deviceName = string.Empty;
    private string _deviceId = string.Empty;
    private string _connection = string.Empty;
    private string _health = string.Empty;
    private string _lastSync = string.Empty;

    public DeviceDetailsViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += (_, snapshot) => Apply(snapshot);

        IdentityFacts = new ObservableCollection<DeviceFact>();
        RuntimeFacts = new ObservableCollection<DeviceFact>();
        NetworkFacts = new ObservableCollection<DeviceFact>();
        SyncFacts = new ObservableCollection<DeviceFact>();

        Apply(_store.Snapshot);
    }

    public ObservableCollection<DeviceFact> IdentityFacts { get; }

    public ObservableCollection<DeviceFact> RuntimeFacts { get; }

    public ObservableCollection<DeviceFact> NetworkFacts { get; }

    public ObservableCollection<DeviceFact> SyncFacts { get; }

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

    public string LastSync
    {
        get => _lastSync;
        private set => SetProperty(ref _lastSync, value);
    }

    private void Apply(AgentStateSnapshot snapshot)
    {
        DeviceName = snapshot.DeviceName;
        DeviceId = snapshot.DeviceId;
        Connection = snapshot.Connection.ToString();
        Health = snapshot.Health.ToString();
        LastSync = snapshot.LastSyncUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss");

        BindCategory(IdentityFacts, snapshot.DeviceFacts, "Identity");
        BindCategory(RuntimeFacts, snapshot.DeviceFacts, "Runtime");
        BindCategory(NetworkFacts, snapshot.DeviceFacts, "Network");
        BindCategory(SyncFacts, snapshot.DeviceFacts, "Sync/Health");
    }

    private static void BindCategory(ObservableCollection<DeviceFact> target, IReadOnlyList<DeviceFact> source, string category)
    {
        target.Clear();
        foreach (var fact in source.Where(f => string.Equals(f.Category, category, StringComparison.OrdinalIgnoreCase)))
        {
            target.Add(fact);
        }
    }
}
