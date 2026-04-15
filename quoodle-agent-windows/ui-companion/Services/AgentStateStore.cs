using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Services;

public sealed class AgentStateStore : IDisposable
{
    private readonly IAgentStateProvider _provider;
    private SynchronizationContext? _uiContext;

    public AgentStateStore(IAgentStateProvider provider)
    {
        _provider = provider;
        _uiContext = SynchronizationContext.Current;
        _provider.SnapshotChanged += HandleSnapshotChanged;
        Snapshot = provider.Snapshot;
    }

    public AgentStateSnapshot Snapshot { get; private set; }

    public event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    public void BindUiContext(SynchronizationContext? context)
    {
        if (context is not null)
        {
            _uiContext = context;
        }
    }

    public void CheckEnrollmentStatus() => _provider.CheckEnrollmentStatus();

    public void BeginPairing() => _provider.BeginPairing();

    public void SelectPairMode(OnboardingPairMode mode) => _provider.SelectPairMode(mode);

    public void SetPairTokenDigits(string tokenDigits) => _provider.SetPairTokenDigits(tokenDigits);

    public void VerifyTokenPairing() => _provider.VerifyTokenPairing();

    public void StartQrPairing() => _provider.StartQrPairing();

    public void RetryPairing() => _provider.RetryPairing();

    public void CompleteEnrollment() => _provider.CompleteEnrollment();

    public void TriggerSyncNow() => _provider.TriggerSyncNow();

    public void UpdateSettings(UiSettings settings) => _provider.UpdateSettings(settings);

    public void SaveTransportConfig(TransportConfig config) => _provider.SaveTransportConfig(config);

    public void SaveSecurityConfig(SecurityConfig config) => _provider.SaveSecurityConfig(config);

    public void SaveTelemetryPolicy(TelemetryPolicyConfig config) => _provider.SaveTelemetryPolicy(config);

    public void SaveNotificationConfig(NotificationPolicyConfig config) => _provider.SaveNotificationConfig(config);

    public void TestTransportConnection() => _provider.TestTransportConnection();

    public void RetryConnection() => _provider.RetryConnection();

    public void BeginRePairFlow() => _provider.BeginRePairFlow();

    public void ResetUiSession() => _provider.ResetUiSession();

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        if (_uiContext is not null && SynchronizationContext.Current != _uiContext)
        {
            _uiContext.Post(static state =>
            {
                if (state is SnapshotDispatch dispatch)
                {
                    dispatch.Store.PublishSnapshot(dispatch.Snapshot);
                }
            }, new SnapshotDispatch(this, snapshot));
            return;
        }

        PublishSnapshot(snapshot);
    }

    private void PublishSnapshot(AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
        SnapshotChanged?.Invoke(this, snapshot);
    }

    public void Dispose()
    {
        _provider.SnapshotChanged -= HandleSnapshotChanged;
        _provider.Dispose();
    }

    private sealed record SnapshotDispatch(AgentStateStore Store, AgentStateSnapshot Snapshot);
}
