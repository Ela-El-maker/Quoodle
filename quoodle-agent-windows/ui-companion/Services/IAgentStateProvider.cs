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

    void SaveTransportConfig(TransportConfig config);

    void SaveSecurityConfig(SecurityConfig config);

    void SaveTelemetryPolicy(TelemetryPolicyConfig config);

    void SaveNotificationConfig(NotificationPolicyConfig config);

    void TestTransportConnection();

    void RetryConnection();

    void BeginRePairFlow();

    void HardResetPairing();

    void ResetUiSession();
}
