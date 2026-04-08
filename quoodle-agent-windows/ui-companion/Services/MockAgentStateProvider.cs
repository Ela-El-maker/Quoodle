using System.Timers;
using Quoodle.Agent.UiCompanion.Models;
using Timer = System.Timers.Timer;

namespace Quoodle.Agent.UiCompanion.Services;

public sealed class MockAgentStateProvider : IAgentStateProvider
{
    private static readonly string[] CommandTemplates =
    {
        "health.sample",
        "sys.info.basic",
        "net.snapshot",
        "proc.snapshot",
        "events.get_stats",
        "policy.sync"
    };

    private static readonly string[] CommandSources =
    {
        "control-plane",
        "scheduler",
        "policy-engine"
    };

    private readonly object _gate = new();
    private readonly Random _random = new();
    private readonly Timer _timer;
    private AgentStateSnapshot _snapshot = AgentStateSnapshot.CreateInitial();
    private int _reconnectHoldTicks;

    public MockAgentStateProvider()
    {
        _timer = new Timer(3000);
        _timer.Elapsed += (_, _) => Tick();

        lock (_gate)
        {
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }
    }

    public AgentStateSnapshot Snapshot
    {
        get
        {
            lock (_gate)
            {
                return _snapshot;
            }
        }
    }

    public event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    public void Start()
    {
        _timer.Start();
        Publish(Snapshot);
    }

    public void Stop()
    {
        _timer.Stop();
    }

    public void AdvanceOnboardingStep()
    {
        lock (_gate)
        {
            var step = Math.Min(6, _snapshot.OnboardingStep + 1);
            _snapshot = _snapshot with { OnboardingStep = step };

            if (step >= 2)
            {
                AddActivityLocked(ActivitySeverity.Info, "ui", "Onboarding progressed", $"Moved to step {step}.");
            }

            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void PreviousOnboardingStep()
    {
        lock (_gate)
        {
            var step = Math.Max(1, _snapshot.OnboardingStep - 1);
            _snapshot = _snapshot with { OnboardingStep = step };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void CompleteOnboarding(string pairingToken)
    {
        lock (_gate)
        {
            var deviceId = string.IsNullOrWhiteSpace(pairingToken)
                ? $"dev-{Guid.NewGuid():N}"[..16]
                : pairingToken.Trim();

            _snapshot = _snapshot with
            {
                IsPaired = true,
                OnboardingStep = 6,
                DeviceId = deviceId,
                Connection = ConnectionState.Connected,
                CurrentActivity = "Connected and monitoring",
                LastSyncUtc = DateTimeOffset.UtcNow,
                LastHeartbeatUtc = DateTimeOffset.UtcNow,
                ReconnectAttempts = 0
            };

            AddActivityLocked(ActivitySeverity.Info, "service", "Pairing completed", "Device successfully enrolled in local mock flow.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void TriggerSyncNow()
    {
        lock (_gate)
        {
            _snapshot = _snapshot with
            {
                LastSyncUtc = DateTimeOffset.UtcNow,
                CurrentActivity = "Manual sync requested"
            };

            AddActivityLocked(ActivitySeverity.Info, "service", "Sync requested", "User initiated manual sync from UI.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void UpdateSettings(UiSettings settings)
    {
        lock (_gate)
        {
            _snapshot = _snapshot with { Settings = settings };
            AddActivityLocked(ActivitySeverity.Info, "ui", "Settings updated", "One or more settings toggles changed.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void RetryConnection()
    {
        lock (_gate)
        {
            _reconnectHoldTicks = 2;
            _snapshot = _snapshot with
            {
                Connection = ConnectionState.Reconnecting,
                CurrentActivity = "Manual reconnect initiated",
                ReconnectAttempts = _snapshot.ReconnectAttempts + 1,
                LastHeartbeatUtc = DateTimeOffset.UtcNow
            };

            AddActivityLocked(ActivitySeverity.Warning, "ui", "Reconnect requested", "User requested connection retry.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void BeginRePairFlow()
    {
        lock (_gate)
        {
            var preservedSettings = _snapshot.Settings;
            var preservedHistory = _snapshot.CommandHistory;
            var nextActivity = _snapshot.Activity.ToList();
            nextActivity.Insert(0, new ActivityEntry(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "ui", "Re-pair started", "Device was moved back to onboarding state."));

            _snapshot = AgentStateSnapshot.CreateInitial() with
            {
                Settings = preservedSettings,
                CommandHistory = preservedHistory,
                Activity = nextActivity.Take(80).ToList(),
                CurrentActivity = "Waiting for re-pairing"
            };

            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void ResetUiSession()
    {
        lock (_gate)
        {
            _reconnectHoldTicks = 0;
            _snapshot = AgentStateSnapshot.CreateInitial();
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    private void Tick()
    {
        lock (_gate)
        {
            var now = DateTimeOffset.UtcNow;

            if (_snapshot.IsPaired)
            {
                var nextConnection = NextConnectionState(_snapshot.Connection);
                var reconnectAttempts = nextConnection == ConnectionState.Reconnecting
                    ? _snapshot.ReconnectAttempts + 1
                    : 0;

                var latency = nextConnection switch
                {
                    ConnectionState.Connected => _random.Next(28, 95),
                    ConnectionState.Reconnecting => _random.Next(180, 760),
                    ConnectionState.Offline => _random.Next(780, 1600),
                    _ => _random.Next(80, 240)
                };

                var cpu = Clamp(_snapshot.CpuPercent + _random.Next(-5, 8), 4, 95);
                var mem = Clamp(_snapshot.MemoryPercent + _random.Next(-3, 6), 20, 92);
                var disk = Clamp(_snapshot.DiskPercent + _random.Next(-1, 2), 40, 96);

                var health = ResolveHealth(cpu, mem, disk, nextConnection);
                var activity = nextConnection switch
                {
                    ConnectionState.Connected => "Monitoring endpoint events",
                    ConnectionState.Reconnecting => "Reconnecting to control plane",
                    ConnectionState.Offline => "Offline; using cached state",
                    ConnectionState.AuthFailed => "Authentication issue detected",
                    _ => "Connecting"
                };

                _snapshot = _snapshot with
                {
                    Connection = nextConnection,
                    Health = health,
                    LastHeartbeatUtc = now,
                    LastSyncUtc = nextConnection == ConnectionState.Connected ? now : _snapshot.LastSyncUtc,
                    ReconnectAttempts = reconnectAttempts,
                    LatencyMs = latency,
                    CpuPercent = cpu,
                    MemoryPercent = mem,
                    DiskPercent = disk,
                    NetworkRxMbps = Math.Round(_random.NextDouble() * 8.4, 2),
                    NetworkTxMbps = Math.Round(_random.NextDouble() * 2.8, 2),
                    CurrentActivity = activity
                };

                AdvanceCommandHistoryLocked(now);

                if (_random.NextDouble() < 0.45)
                {
                    var severity = health switch
                    {
                        HealthState.Critical => ActivitySeverity.Error,
                        HealthState.Warning => ActivitySeverity.Warning,
                        _ => ActivitySeverity.Info
                    };
                    AddActivityLocked(severity, "service", "Heartbeat sample", activity);
                }
            }
            else
            {
                _snapshot = _snapshot with
                {
                    LastHeartbeatUtc = now,
                    CurrentActivity = "Waiting for pairing"
                };
            }

            RebuildDeviceFactsLocked(now);
        }

        Publish(Snapshot);
    }

    private ConnectionState NextConnectionState(ConnectionState current)
    {
        if (_reconnectHoldTicks > 0)
        {
            _reconnectHoldTicks -= 1;
            return ConnectionState.Reconnecting;
        }

        if (current == ConnectionState.Reconnecting)
        {
            return ConnectionState.Connected;
        }

        if (_random.NextDouble() > 0.78)
        {
            return current switch
            {
                ConnectionState.Connected => ConnectionState.Reconnecting,
                ConnectionState.Offline => ConnectionState.Reconnecting,
                _ => ConnectionState.Connected
            };
        }

        if (_random.NextDouble() > 0.94)
        {
            return ConnectionState.Offline;
        }

        return current == ConnectionState.Connecting ? ConnectionState.Connected : current;
    }

    private void AdvanceCommandHistoryLocked(DateTimeOffset now)
    {
        var history = _snapshot.CommandHistory.ToList();
        var changed = false;

        for (var i = 0; i < history.Count; i++)
        {
            var entry = history[i];

            switch (entry.Status)
            {
                case CommandExecutionStatus.Queued when _random.NextDouble() > 0.45:
                    history[i] = entry with { Status = CommandExecutionStatus.Dispatched };
                    changed = true;
                    break;

                case CommandExecutionStatus.Dispatched when _random.NextDouble() > 0.40:
                    history[i] = entry with { Status = CommandExecutionStatus.Executing };
                    changed = true;
                    break;

                case CommandExecutionStatus.Executing:
                    var runningDuration = entry.DurationMs + _random.Next(80, 360);
                    if (_random.NextDouble() > 0.45)
                    {
                        var terminal = ResolveTerminalStatus();
                        var error = terminal switch
                        {
                            CommandExecutionStatus.Failed => "Remote execution failed in mock runtime.",
                            CommandExecutionStatus.TimedOut => "Command timed out while awaiting completion.",
                            CommandExecutionStatus.Rejected => "Command rejected by policy gate.",
                            _ => string.Empty
                        };

                        history[i] = entry with { Status = terminal, DurationMs = runningDuration, ErrorMessage = error };
                        changed = true;

                        if (terminal is CommandExecutionStatus.Failed or CommandExecutionStatus.TimedOut or CommandExecutionStatus.Rejected)
                        {
                            AddActivityLocked(ActivitySeverity.Warning, "command", "Command issue", $"{entry.Command}: {terminal}");
                        }
                    }
                    else
                    {
                        history[i] = entry with { DurationMs = runningDuration };
                        changed = true;
                    }
                    break;
            }
        }

        var activeCount = history.Count(x => x.Status is CommandExecutionStatus.Queued or CommandExecutionStatus.Dispatched or CommandExecutionStatus.Executing);
        if (activeCount < 3 && _random.NextDouble() > 0.60)
        {
            var newEntry = new CommandExecutionEntry(
                Id: $"cmd-{Guid.NewGuid():N}"[..16],
                IssuedAtUtc: now,
                Command: CommandTemplates[_random.Next(CommandTemplates.Length)],
                Status: CommandExecutionStatus.Queued,
                Source: CommandSources[_random.Next(CommandSources.Length)],
                DurationMs: 0,
                ErrorMessage: string.Empty);

            history.Insert(0, newEntry);
            changed = true;
        }

        if (history.Count > 100)
        {
            history = history.Take(100).ToList();
            changed = true;
        }

        if (changed)
        {
            _snapshot = _snapshot with { CommandHistory = history };
        }
    }

    private static CommandExecutionStatus ResolveTerminalStatus()
    {
        var roll = Random.Shared.Next(100);
        if (roll < 72) return CommandExecutionStatus.Succeeded;
        if (roll < 86) return CommandExecutionStatus.Failed;
        if (roll < 95) return CommandExecutionStatus.TimedOut;
        return CommandExecutionStatus.Rejected;
    }

    private static HealthState ResolveHealth(int cpu, int memory, int disk, ConnectionState connection)
    {
        if (connection == ConnectionState.Offline || cpu > 86 || memory > 88 || disk > 94)
        {
            return HealthState.Critical;
        }

        if (connection == ConnectionState.Reconnecting || cpu > 72 || memory > 78 || disk > 90)
        {
            return HealthState.Warning;
        }

        return HealthState.Healthy;
    }

    private void RebuildDeviceFactsLocked(DateTimeOffset now)
    {
        var facts = new List<DeviceFact>
        {
            new("Identity", "Device Name", _snapshot.DeviceName),
            new("Identity", "Device ID", _snapshot.DeviceId),
            new("Identity", "Agent Version", _snapshot.AgentVersion),
            new("Runtime", "Pairing State", _snapshot.IsPaired ? "Paired" : "Not paired"),
            new("Runtime", "Connection", _snapshot.Connection.ToString()),
            new("Runtime", "Current Activity", _snapshot.CurrentActivity),
            new("Network", "Latency", $"{_snapshot.LatencyMs} ms"),
            new("Network", "RX/TX", $"{_snapshot.NetworkRxMbps:F2} / {_snapshot.NetworkTxMbps:F2} Mbps"),
            new("Sync/Health", "Health", _snapshot.Health.ToString()),
            new("Sync/Health", "CPU / Memory / Disk", $"{_snapshot.CpuPercent}% / {_snapshot.MemoryPercent}% / {_snapshot.DiskPercent}%"),
            new("Sync/Health", "Last Heartbeat", _snapshot.LastHeartbeatUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")),
            new("Sync/Health", "Last Sync", _snapshot.LastSyncUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")),
            new("Sync/Health", "Snapshot Updated", now.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"))
        };

        _snapshot = _snapshot with { DeviceFacts = facts };
    }

    private void AddActivityLocked(ActivitySeverity severity, string source, string title, string details)
    {
        var next = _snapshot.Activity.ToList();
        next.Insert(0, new ActivityEntry(DateTimeOffset.UtcNow, severity, source, title, details));
        if (next.Count > 80)
        {
            next = next.Take(80).ToList();
        }

        _snapshot = _snapshot with { Activity = next };
    }

    private static int Clamp(int value, int min, int max) => Math.Max(min, Math.Min(max, value));

    private void Publish(AgentStateSnapshot snapshot)
    {
        SnapshotChanged?.Invoke(this, snapshot);
    }

    public void Dispose()
    {
        _timer.Stop();
        _timer.Dispose();
    }
}
