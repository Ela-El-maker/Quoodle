using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Services;

public interface IAgentStateProvider : IDisposable
{
    AgentStateSnapshot Snapshot { get; }

    event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    void Start();

    void Stop();

    void AdvanceOnboardingStep();

    void PreviousOnboardingStep();

    void CompleteOnboarding(string pairingToken);

    void TriggerSyncNow();

    void UpdateSettings(UiSettings settings);

    void RetryConnection();

    void BeginRePairFlow();

    void ResetUiSession();
}
