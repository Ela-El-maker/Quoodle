using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using Quoodle.Agent.UiCompanion.ViewModels;
using Xunit;

namespace Quoodle.Agent.UiCompanion.Tests;

public sealed class DashboardViewModelTests
{
    [Fact]
    public void AggregatesMetricCardsFromSnapshot()
    {
        var now = DateTimeOffset.UtcNow;
        var snapshot = BuildSnapshot(
            now,
            commandHistory:
            [
                new CommandExecutionEntry("cmd-1", now.AddMinutes(-10), "lock_screen", CommandExecutionStatus.Succeeded, "control-plane", 1120, string.Empty),
                new CommandExecutionEntry("cmd-2", now.AddMinutes(-8), "ping", CommandExecutionStatus.Failed, "scheduler", 250, "timeout")
            ],
            activity:
            [
                new ActivityEntry(now.AddMinutes(-7), ActivitySeverity.Info, "kernel", "Kernel opcode", "kernel event observed")
            ],
            cpu: 12,
            memory: 45,
            disk: 60,
            rx: 1.8,
            tx: 2.3);

        var provider = new TestProvider(snapshot);
        using var store = new AgentStateStore(provider);
        using var vm = new DashboardViewModel(store);

        Assert.Equal("1", vm.FailedCommandsCard.Value);
        Assert.Equal("1", vm.CommandsCompletedCard.Value);
        Assert.Equal("12%", vm.CpuUsageCard.Value);
        Assert.Equal("45%", vm.RamUsageCard.Value);
        Assert.Equal("60%", vm.DiskUsageCard.Value);
        Assert.Equal("2.3 Mbps", vm.NetTxCard.Value);
        Assert.Equal("1.8 Mbps", vm.NetRxCard.Value);
    }

    [Fact]
    public void TelemetrySeriesIsBoundedAndNonEmptyAfterManyUpdates()
    {
        var now = DateTimeOffset.UtcNow;
        var initial = BuildSnapshot(now);
        var provider = new TestProvider(initial);
        using var store = new AgentStateStore(provider);
        using var vm = new DashboardViewModel(store);

        for (var i = 0; i < 120; i++)
        {
            var sample = BuildSnapshot(
                now.AddSeconds(i),
                cpu: 10 + (i % 20),
                memory: 30 + (i % 25),
                rx: 1.1 + (i % 7) * 0.1,
                tx: 2.0 + (i % 5) * 0.1);
            provider.Push(sample);
        }

        Assert.NotEmpty(vm.TelemetrySeries);
        Assert.True(vm.TelemetrySeries.Count <= 64);
    }

    [Fact]
    public void BuildsHourlyCommandBinsWithCompletedAndFailedCounts()
    {
        var now = DateTimeOffset.UtcNow;
        var history = new List<CommandExecutionEntry>();
        for (var i = 0; i < 11; i++)
        {
            history.Add(new CommandExecutionEntry(
                $"cmd-c-{i}",
                now.AddHours(-i),
                "health.sample",
                CommandExecutionStatus.Succeeded,
                "control-plane",
                100 + i,
                string.Empty));

            if (i % 3 == 0)
            {
                history.Add(new CommandExecutionEntry(
                    $"cmd-f-{i}",
                    now.AddHours(-i).AddMinutes(10),
                    "ping",
                    CommandExecutionStatus.Failed,
                    "scheduler",
                    220,
                    "failed"));
            }
        }

        var provider = new TestProvider(BuildSnapshot(now, commandHistory: history));
        using var store = new AgentStateStore(provider);
        using var vm = new DashboardViewModel(store);

        Assert.Equal(11, vm.CommandBins.Count);
        Assert.True(vm.CommandBins.Sum(x => x.Completed) >= 10);
        Assert.True(vm.CommandBins.Sum(x => x.Failed) >= 3);
    }

    [Fact]
    public void MapsFeedItemsAndLastCommandFromActivityAndHistory()
    {
        var now = DateTimeOffset.UtcNow;
        var snapshot = BuildSnapshot(
            now,
            commandHistory:
            [
                new CommandExecutionEntry("cmd-100", now.AddMinutes(-2), "lock_screen", CommandExecutionStatus.Succeeded, "control-plane", 900, string.Empty),
                new CommandExecutionEntry("cmd-099", now.AddMinutes(-4), "ping", CommandExecutionStatus.Failed, "scheduler", 300, "err=4004")
            ],
            activity:
            [
                new ActivityEntry(now.AddMinutes(-1), ActivitySeverity.Info, "service", "Heartbeat sample", "heartbeat alive"),
                new ActivityEntry(now.AddMinutes(-3), ActivitySeverity.Info, "service", "Telemetry sample", "telemetry basic"),
                new ActivityEntry(now.AddMinutes(-5), ActivitySeverity.Warning, "kernel", "Kernel event", "kernel opcode")
            ]);

        var provider = new TestProvider(snapshot);
        using var store = new AgentStateStore(provider);
        using var vm = new DashboardViewModel(store);

        Assert.NotEmpty(vm.WssFeedItems);
        Assert.Contains(vm.WssFeedItems, x => x.Type == DashboardFeedType.Heartbeat);
        Assert.Contains(vm.WssFeedItems, x => x.Type == DashboardFeedType.CommandResult);

        Assert.Equal("Completed", vm.LastCommand.StatusLabel);
        Assert.Equal("lock screen", vm.LastCommand.Command);
        Assert.Equal("result.status = ok", vm.LastCommand.ResultLine);
    }

    private static AgentStateSnapshot BuildSnapshot(
        DateTimeOffset now,
        IReadOnlyList<CommandExecutionEntry>? commandHistory = null,
        IReadOnlyList<ActivityEntry>? activity = null,
        int cpu = 15,
        int memory = 40,
        int disk = 58,
        double rx = 1.2,
        double tx = 2.1)
    {
        return AgentStateSnapshot.CreateInitial() with
        {
            IsPaired = true,
            DeviceId = "PC001",
            DeviceName = "WORKSTATION-PC001",
            AgentVersion = "0.0.1",
            PolicyHash = "sha256:policy123",
            Connection = ConnectionState.Connected,
            LastSyncUtc = now,
            LastHeartbeatUtc = now.AddSeconds(-18),
            ReconnectAttempts = 0,
            CpuPercent = cpu,
            MemoryPercent = memory,
            DiskPercent = disk,
            NetworkRxMbps = rx,
            NetworkTxMbps = tx,
            CommandHistory = commandHistory ?? Array.Empty<CommandExecutionEntry>(),
            Activity = activity ?? Array.Empty<ActivityEntry>()
        };
    }
}

internal sealed class TestProvider : IAgentStateProvider
{
    public TestProvider(AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
    }

    public AgentStateSnapshot Snapshot { get; private set; }

    public event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    public void Start()
    {
    }

    public void Stop()
    {
    }

    public void CheckEnrollmentStatus()
    {
    }

    public void BeginPairing()
    {
    }

    public void SelectPairMode(OnboardingPairMode mode)
    {
    }

    public void SetPairTokenDigits(string tokenDigits)
    {
    }

    public void VerifyTokenPairing()
    {
    }

    public void StartQrPairing()
    {
    }

    public void RetryPairing()
    {
    }

    public void CompleteEnrollment()
    {
    }

    public void TriggerSyncNow()
    {
    }

    public void UpdateSettings(UiSettings settings)
    {
    }

    public void SaveTransportConfig(TransportConfig config)
    {
    }

    public void SaveSecurityConfig(SecurityConfig config)
    {
    }

    public void SaveTelemetryPolicy(TelemetryPolicyConfig config)
    {
    }

    public void SaveNotificationConfig(NotificationPolicyConfig config)
    {
    }

    public void TestTransportConnection()
    {
    }

    public void RetryConnection()
    {
    }

    public void BeginRePairFlow()
    {
    }

    public void ResetUiSession()
    {
    }

    public void Push(AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
        SnapshotChanged?.Invoke(this, snapshot);
    }

    public void Dispose()
    {
    }
}
