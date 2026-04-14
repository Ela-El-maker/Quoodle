namespace Quoodle.Agent.UiCompanion.Models;

public sealed record AgentStateSnapshot(
    bool IsPaired,
    OnboardingFlowState Onboarding,
    string DeviceId,
    string DeviceName,
    string AgentVersion,
    string PolicyHash,
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
    IReadOnlyList<WssMessageLogRow> WssMessageLog,
    IReadOnlyList<CommandHistoryRow> CommandHistoryLog,
    IReadOnlyList<KernelEventRow> KernelEvents,
    AgentConfiguration Configuration,
    UiSettings Settings)
{
    public static AgentStateSnapshot CreateInitial() => new(
        IsPaired: false,
        Onboarding: OnboardingFlowState.CreateInitial(),
        DeviceId: "pending-pairing",
        DeviceName: Environment.MachineName,
        AgentVersion: "0.1.0-ui-m1",
        PolicyHash: "sha256:pending",
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
        WssMessageLog: Array.Empty<WssMessageLogRow>(),
        CommandHistoryLog: Array.Empty<CommandHistoryRow>(),
        KernelEvents: Array.Empty<KernelEventRow>(),
        Configuration: AgentConfiguration.CreateDefault(
            now: DateTimeOffset.UtcNow,
            deviceId: "pending-pairing",
            deviceName: Environment.MachineName,
            agentVersion: "0.1.0-ui-m1",
            isEnrolled: false),
        Settings: UiSettings.Default);
}
