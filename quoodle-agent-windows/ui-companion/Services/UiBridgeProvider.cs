using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Services;

public sealed class UiBridgeProvider : IAgentStateProvider
{
    public AgentStateSnapshot Snapshot { get; private set; } = AgentStateSnapshot.CreateInitial();

    public event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    public void Start()
    {
        // Future: attach named pipe bridge to service authority.
    }

    public void Stop()
    {
    }

    public void AdvanceOnboardingStep() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void PreviousOnboardingStep() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void CompleteOnboarding(string pairingToken) => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void TriggerSyncNow() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void UpdateSettings(UiSettings settings) => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void RetryConnection() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void BeginRePairFlow() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void ResetUiSession() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void Dispose()
    {
    }

    private void Publish(AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
        SnapshotChanged?.Invoke(this, snapshot);
    }
}
