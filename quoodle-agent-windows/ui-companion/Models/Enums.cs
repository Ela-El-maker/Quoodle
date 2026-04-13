namespace Quoodle.Agent.UiCompanion.Models;

public enum ConnectionState
{
    Connected,
    Connecting,
    Reconnecting,
    Offline,
    AuthFailed
}

public enum HealthState
{
    Healthy,
    Warning,
    Critical
}

public enum ActivitySeverity
{
    Info,
    Warning,
    Error
}

public enum CommandExecutionStatus
{
    Queued,
    Dispatched,
    Executing,
    Succeeded,
    Failed,
    TimedOut,
    Rejected
}

public enum OnboardingStage
{
    Detect,
    Pair,
    Confirm
}

public enum OnboardingDetectState
{
    Idle,
    Checking,
    NotEnrolled
}

public enum OnboardingPairMode
{
    Token,
    Qr
}

public enum OnboardingPairState
{
    TokenEntry,
    TokenVerifying,
    TokenFailed,
    QrWaiting,
    PairSucceeded
}

public enum OnboardingConfirmState
{
    Registering,
    EnrollmentComplete
}
