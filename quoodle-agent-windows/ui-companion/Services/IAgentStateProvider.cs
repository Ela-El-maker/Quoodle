using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Services;

public interface IAgentStateProvider : IDisposable
{
    AgentStateSnapshot Snapshot { get; }

    event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    void Start();

    void Stop();

    void CheckEnrollmentStatus();

    void BeginPairing();

    void SelectPairMode(OnboardingPairMode mode);

    void SetPairTokenDigits(string tokenDigits);

    void VerifyTokenPairing();

    void StartQrPairing();

    void RetryPairing();

    void CompleteEnrollment();

    void TriggerSyncNow();

    void UpdateSettings(UiSettings settings);

    void RetryConnection();

    void BeginRePairFlow();

    void ResetUiSession();
}
