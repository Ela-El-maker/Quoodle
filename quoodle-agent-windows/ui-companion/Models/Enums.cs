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
