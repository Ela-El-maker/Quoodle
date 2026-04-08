namespace Quoodle.Agent.UiCompanion.Models;

public sealed record AgentStateSnapshot(
    bool IsPaired,
    int OnboardingStep,
    string DeviceId,
    string DeviceName,
    string AgentVersion,
    ConnectionState Connection,
    HealthState Health,
    DateTimeOffset LastSyncUtc,
    DateTimeOffset LastHeartbeatUtc,
    int ReconnectAttempts,
    int LatencyMs,
    int CpuPercent,
    int MemoryPercent,
    int DiskPercent,
    double NetworkRxMbps,
    double NetworkTxMbps,
    string CurrentActivity,
    IReadOnlyList<ActivityEntry> Activity,
    IReadOnlyList<DeviceFact> DeviceFacts,
    IReadOnlyList<CommandExecutionEntry> CommandHistory,
    UiSettings Settings)
{
    public static AgentStateSnapshot CreateInitial() => new(
        IsPaired: false,
        OnboardingStep: 1,
        DeviceId: "pending-pairing",
        DeviceName: Environment.MachineName,
        AgentVersion: "0.1.0-ui-m1",
        Connection: ConnectionState.Connecting,
        Health: HealthState.Healthy,
        LastSyncUtc: DateTimeOffset.UtcNow,
        LastHeartbeatUtc: DateTimeOffset.UtcNow,
        ReconnectAttempts: 0,
        LatencyMs: 45,
        CpuPercent: 12,
        MemoryPercent: 34,
        DiskPercent: 57,
        NetworkRxMbps: 1.2,
        NetworkTxMbps: 0.4,
        CurrentActivity: "Waiting for pairing",
        Activity: new List<ActivityEntry>
        {
            new(DateTimeOffset.UtcNow, ActivitySeverity.Info, "service", "UI companion started", "Local mock provider initialized.")
        },
        DeviceFacts: new List<DeviceFact>
        {
            new("Identity", "Device Name", Environment.MachineName),
            new("Identity", "Device ID", "pending-pairing"),
            new("Identity", "Agent Version", "0.1.0-ui-m1"),
            new("Runtime", "Pairing State", "Not paired"),
            new("Runtime", "Connection", "Connecting"),
            new("Network", "Latency", "45 ms"),
            new("Network", "RX/TX", "1.20 / 0.40 Mbps"),
            new("Sync/Health", "Health", "Healthy"),
            new("Sync/Health", "Last Heartbeat", DateTimeOffset.UtcNow.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")),
            new("Sync/Health", "Last Sync", DateTimeOffset.UtcNow.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"))
        },
        CommandHistory: new List<CommandExecutionEntry>
        {
            new(
                Id: $"cmd-{Guid.NewGuid():N}"[..16],
                IssuedAtUtc: DateTimeOffset.UtcNow,
                Command: "health.sample",
                Status: CommandExecutionStatus.Succeeded,
                Source: "bootstrap",
                DurationMs: 142,
                ErrorMessage: string.Empty)
        },
        Settings: UiSettings.Default);
}
