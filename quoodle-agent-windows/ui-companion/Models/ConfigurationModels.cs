namespace Quoodle.Agent.UiCompanion.Models;

public sealed record DeviceIdentityConfig(
    string DeviceId,
    string EnrolledAccount,
    string HwidHash,
    string AttestationHash,
    string AgentVersion,
    string OsBuild,
    string LocalStoragePath,
    DateTimeOffset? EnrolledAtUtc,
    string EnrolledState);

public sealed record TransportConfig(
    string Endpoint,
    string EndpointEnvTag,
    int HeartbeatIntervalSeconds,
    int ConnectTimeoutMs,
    int ReconnectMaxAttempts,
    int ReconnectInitialDelayMs,
    int ReconnectMaxDelayMs,
    int ReconnectJitterMs,
    IReadOnlyList<string> EnvironmentTags);

public sealed record SecurityPolicyGates(
    bool CanEditAllowUserExit,
    string AllowUserExitTag,
    string AllowUserExitReason);

public sealed record SecurityConfig(
    bool KernelGuardEnabled,
    bool RequireCommandSignature,
    bool RequireKernelSignature,
    bool ReplayProtection,
    bool AllowUserExit,
    string KernelGuardTag,
    string RequireCommandSignatureTag,
    string RequireKernelSignatureTag,
    string SigningAlgorithm,
    SecurityPolicyGates PolicyGates);

public sealed record TelemetryPolicyConfig(
    int TelemetryIntervalSeconds,
    int HeartbeatIntervalSeconds,
    bool CpuMetrics,
    bool RamMetrics,
    bool DiskUsage,
    bool NetworkThroughput,
    bool KernelEvents,
    string CpuScopeLabel,
    string RamScopeLabel,
    string DiskScopeLabel,
    string NetworkScopeLabel,
    string KernelScopeLabel);

public sealed record NotificationPolicyConfig(
    bool NotifyCommandExecutionFailed,
    bool NotifyAuthFailed,
    bool NotifyPolicyHashMismatch,
    bool NotifyConnectionDegraded,
    bool NotifyConnectionRecovered,
    bool NotifyKernelEventReceived,
    bool NotifyCommandCompletedSuccessfully,
    int ReconnectWarningThresholdSeconds,
    int RateLimitWindowMinutes);

public sealed record AgentConfiguration(
    DeviceIdentityConfig DeviceIdentity,
    TransportConfig Transport,
    SecurityConfig Security,
    TelemetryPolicyConfig TelemetryPolicy,
    NotificationPolicyConfig Notifications)
{
    public static AgentConfiguration CreateDefault(
        DateTimeOffset now,
        string deviceId,
        string deviceName,
        string agentVersion,
        bool isEnrolled)
    {
        var safeDeviceId = string.IsNullOrWhiteSpace(deviceId) ? "pending-pairing" : deviceId;
        var machineLabel = string.IsNullOrWhiteSpace(deviceName) ? Environment.MachineName : deviceName;
        DateTimeOffset? enrolledAt = isEnrolled ? now : null;

        var identity = new DeviceIdentityConfig(
            DeviceId: safeDeviceId,
            EnrolledAccount: isEnrolled ? "operator@corp.quoodle.io" : "pending@quoodle.local",
            HwidHash: $"sha256:{ShortHash($"hwid::{safeDeviceId}::{machineLabel}")}",
            AttestationHash: $"sha256:{ShortHash($"attest::{safeDeviceId}::{agentVersion}")}",
            AgentVersion: string.IsNullOrWhiteSpace(agentVersion) ? "v0.0.1" : $"v{agentVersion}",
            OsBuild: Environment.OSVersion.VersionString.Replace("Microsoft Windows", "Windows").Trim(),
            LocalStoragePath: Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Quoodle", "device_id"),
            EnrolledAtUtc: enrolledAt,
            EnrolledState: isEnrolled ? "Enrolled" : "Not Enrolled");

        var transport = new TransportConfig(
            Endpoint: "wss://gateway.quoodle.io/agent",
            EndpointEnvTag: "AGENT_ENDPOINT",
            HeartbeatIntervalSeconds: 30,
            ConnectTimeoutMs: 10000,
            ReconnectMaxAttempts: 20,
            ReconnectInitialDelayMs: 1000,
            ReconnectMaxDelayMs: 30000,
            ReconnectJitterMs: 500,
            EnvironmentTags: new[] { "prod", "windows", "desktop" });

        var security = new SecurityConfig(
            KernelGuardEnabled: true,
            RequireCommandSignature: true,
            RequireKernelSignature: false,
            ReplayProtection: true,
            AllowUserExit: false,
            KernelGuardTag: "QUOODLE_USE_KERNEL_DRIVER",
            RequireCommandSignatureTag: "AGENT_REQUIRE_COMMAND_SIGNATURE",
            RequireKernelSignatureTag: "AGENT_REQUIRE_KERNEL_SIGNATURE",
            SigningAlgorithm: "Ed25519",
            PolicyGates: new SecurityPolicyGates(
                CanEditAllowUserExit: false,
                AllowUserExitTag: "policy-gated",
                AllowUserExitReason: "Restricted by policy capability allow_user_exit=false"));

        var telemetry = new TelemetryPolicyConfig(
            TelemetryIntervalSeconds: 60,
            HeartbeatIntervalSeconds: 30,
            CpuMetrics: true,
            RamMetrics: true,
            DiskUsage: true,
            NetworkThroughput: true,
            KernelEvents: true,
            CpuScopeLabel: "telemetry_basic.cpu",
            RamScopeLabel: "telemetry_basic.ram",
            DiskScopeLabel: "telemetry_basic.disk_usage",
            NetworkScopeLabel: "telemetry_basic.network_*",
            KernelScopeLabel: "kernel_event");

        var notifications = new NotificationPolicyConfig(
            NotifyCommandExecutionFailed: true,
            NotifyAuthFailed: true,
            NotifyPolicyHashMismatch: true,
            NotifyConnectionDegraded: true,
            NotifyConnectionRecovered: true,
            NotifyKernelEventReceived: false,
            NotifyCommandCompletedSuccessfully: false,
            ReconnectWarningThresholdSeconds: 120,
            RateLimitWindowMinutes: 10);

        return new AgentConfiguration(identity, transport, security, telemetry, notifications);
    }

    private static string ShortHash(string input)
    {
        var chars = input.ToCharArray();
        var value = 2166136261u;
        foreach (var c in chars)
        {
            value ^= c;
            value *= 16777619;
        }

        return $"{value:x8}{value ^ 0x9e3779b9u:x8}{value ^ 0x85ebca6bu:x8}{value ^ 0xc2b2ae35u:x8}";
    }
}
