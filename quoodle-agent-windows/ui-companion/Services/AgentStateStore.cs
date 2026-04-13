using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Services;

public sealed class AgentStateStore : IDisposable
{
    private readonly IAgentStateProvider _provider;

    public AgentStateStore(IAgentStateProvider provider)
    {
        _provider = provider;
        _provider.SnapshotChanged += HandleSnapshotChanged;
        Snapshot = provider.Snapshot;
    }

    public AgentStateSnapshot Snapshot { get; private set; }

    public event EventHandler<AgentStateSnapshot>? SnapshotChanged;

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

    public void RetryConnection() => _provider.RetryConnection();

    public void BeginRePairFlow() => _provider.BeginRePairFlow();

    public void ResetUiSession() => _provider.ResetUiSession();

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
        SnapshotChanged?.Invoke(this, snapshot);
    }

    public void Dispose()
    {
        _provider.SnapshotChanged -= HandleSnapshotChanged;
        _provider.Dispose();
    }
}
