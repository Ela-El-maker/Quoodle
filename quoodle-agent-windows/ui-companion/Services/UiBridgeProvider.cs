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

    public void CheckEnrollmentStatus() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void BeginPairing() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void SelectPairMode(OnboardingPairMode mode) => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void SetPairTokenDigits(string tokenDigits) => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void VerifyTokenPairing() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void StartQrPairing() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void RetryPairing() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

    public void CompleteEnrollment() => throw new NotImplementedException("UiBridgeProvider is a future live provider.");

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
