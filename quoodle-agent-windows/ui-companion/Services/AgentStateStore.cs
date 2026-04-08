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

    public void AdvanceOnboardingStep() => _provider.AdvanceOnboardingStep();

    public void PreviousOnboardingStep() => _provider.PreviousOnboardingStep();

    public void CompleteOnboarding(string pairingToken) => _provider.CompleteOnboarding(pairingToken);

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
