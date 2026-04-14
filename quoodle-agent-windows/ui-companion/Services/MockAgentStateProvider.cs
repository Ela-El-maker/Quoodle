using System.Timers;
using Quoodle.Agent.UiCompanion.Models;
using Timer = System.Timers.Timer;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Quoodle.Agent.UiCompanion.Services;

public sealed class MockAgentStateProvider : IAgentStateProvider
{
    private const string ExpectedPairCode = "123456";
    private const string MockDeviceId = "PC001-A3F9-2B7C";
    private const string MockDeviceName = "WORKSTATION-PC001";
    private const string MockPolicyHash = "sha256:a1b2c3d4e5f6";

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
    private int _onboardingOperationId;
    private static readonly JsonSerializerOptions JsonPretty = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public MockAgentStateProvider()
    {
        _timer = new Timer(3000);
        _timer.Elapsed += (_, _) => Tick();

        lock (_gate)
        {
            RefreshLegacySettingsFromConfigurationLocked();
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

    public void CheckEnrollmentStatus()
    {
        int operationId;
        lock (_gate)
        {
            if (_snapshot.IsPaired)
            {
                return;
            }

            operationId = ++_onboardingOperationId;
            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    Stage = OnboardingStage.Detect,
                    DetectState = OnboardingDetectState.Checking,
                    PairError = string.Empty
                },
                CurrentActivity = "Checking enrollment status"
            };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
        _ = SimulateDetectResultAsync(operationId);
    }

    public void BeginPairing()
    {
        lock (_gate)
        {
            if (_snapshot.IsPaired)
            {
                return;
            }

            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    Stage = OnboardingStage.Pair,
                    DetectState = OnboardingDetectState.NotEnrolled,
                    PairMode = OnboardingPairMode.Token,
                    PairState = OnboardingPairState.TokenEntry,
                    ConfirmState = OnboardingConfirmState.Registering,
                    TokenDigits = string.Empty,
                    PairError = string.Empty,
                    PairingString = BuildPairingStringLocked(),
                    EnrolledAtUtc = null
                },
                CurrentActivity = "Awaiting pair code or QR scan"
            };

            AddActivityLocked(ActivitySeverity.Info, "ui", "Pairing started", "User opened pair step.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void SelectPairMode(OnboardingPairMode mode)
    {
        lock (_gate)
        {
            if (_snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            if (_snapshot.Onboarding.PairMode != mode)
            {
                _onboardingOperationId += 1;
            }

            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    PairMode = mode,
                    PairState = mode == OnboardingPairMode.Qr ? OnboardingPairState.QrWaiting : OnboardingPairState.TokenEntry,
                    PairError = string.Empty,
                    PairingString = BuildPairingStringLocked()
                },
                CurrentActivity = mode == OnboardingPairMode.Qr ? "Waiting for QR scan confirmation" : "Awaiting 6-digit pair code"
            };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void SetPairTokenDigits(string tokenDigits)
    {
        lock (_gate)
        {
            if (_snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            var sanitized = new string((tokenDigits ?? string.Empty).Where(char.IsDigit).Take(6).ToArray());
            var pairState = _snapshot.Onboarding.PairState == OnboardingPairState.TokenVerifying
                ? OnboardingPairState.TokenVerifying
                : OnboardingPairState.TokenEntry;

            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    PairMode = OnboardingPairMode.Token,
                    PairState = pairState,
                    TokenDigits = sanitized,
                    PairError = string.Empty
                }
            };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void VerifyTokenPairing()
    {
        int operationId;
        string token;
        lock (_gate)
        {
            if (_snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            token = _snapshot.Onboarding.TokenDigits;
            if (token.Length != 6)
            {
                return;
            }

            operationId = ++_onboardingOperationId;
            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    PairMode = OnboardingPairMode.Token,
                    PairState = OnboardingPairState.TokenVerifying,
                    PairError = string.Empty
                },
                CurrentActivity = "Verifying pair code"
            };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
        _ = SimulateTokenVerificationAsync(operationId, token);
    }

    public void StartQrPairing()
    {
        int operationId;
        lock (_gate)
        {
            if (_snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            operationId = ++_onboardingOperationId;
            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    PairMode = OnboardingPairMode.Qr,
                    PairState = OnboardingPairState.QrWaiting,
                    PairError = string.Empty,
                    TokenDigits = string.Empty,
                    PairingString = BuildPairingStringLocked()
                },
                CurrentActivity = "Waiting for QR scan confirmation"
            };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
        _ = SimulateQrPairingAsync(operationId);
    }

    public void RetryPairing()
    {
        lock (_gate)
        {
            if (_snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            _onboardingOperationId += 1;
            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    PairMode = OnboardingPairMode.Token,
                    PairState = OnboardingPairState.TokenEntry,
                    PairError = string.Empty,
                    TokenDigits = string.Empty
                },
                CurrentActivity = "Retry pairing with a new code"
            };
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void CompleteEnrollment()
    {
        lock (_gate)
        {
            if (_snapshot.Onboarding.Stage != OnboardingStage.Confirm)
            {
                return;
            }

            ApplyEnrollmentCompleteLocked(DateTimeOffset.UtcNow);
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
            var currentConfig = _snapshot.Configuration;
            var updatedNotifications = currentConfig.Notifications with
            {
                NotifyConnectionRecovered = settings.NotifyInfo,
                NotifyKernelEventReceived = settings.NotifyInfo && currentConfig.Notifications.NotifyKernelEventReceived,
                NotifyCommandCompletedSuccessfully = settings.NotifyInfo && currentConfig.Notifications.NotifyCommandCompletedSuccessfully,
                NotifyCommandExecutionFailed = settings.NotifyWarningsAndCritical,
                NotifyAuthFailed = settings.NotifyWarningsAndCritical,
                NotifyPolicyHashMismatch = settings.NotifyWarningsAndCritical,
                NotifyConnectionDegraded = settings.NotifyWarningsAndCritical
            };
            var updatedSecurity = currentConfig.Security with
            {
                KernelGuardEnabled = settings.CollectDiagnostics
            };

            _snapshot = _snapshot with
            {
                Configuration = currentConfig with
                {
                    Notifications = updatedNotifications,
                    Security = updatedSecurity
                },
                Settings = settings
            };
            AddActivityLocked(ActivitySeverity.Info, "ui", "Settings updated", "One or more settings toggles changed.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void SaveTransportConfig(TransportConfig config)
    {
        lock (_gate)
        {
            var existing = _snapshot.Configuration.Transport;
            var normalized = config with
            {
                Endpoint = string.IsNullOrWhiteSpace(config.Endpoint) ? existing.Endpoint : config.Endpoint.Trim(),
                EndpointEnvTag = string.IsNullOrWhiteSpace(config.EndpointEnvTag) ? existing.EndpointEnvTag : config.EndpointEnvTag.Trim(),
                HeartbeatIntervalSeconds = PositiveOrFallback(config.HeartbeatIntervalSeconds, existing.HeartbeatIntervalSeconds),
                ConnectTimeoutMs = PositiveOrFallback(config.ConnectTimeoutMs, existing.ConnectTimeoutMs),
                ReconnectMaxAttempts = PositiveOrFallback(config.ReconnectMaxAttempts, existing.ReconnectMaxAttempts),
                ReconnectInitialDelayMs = PositiveOrFallback(config.ReconnectInitialDelayMs, existing.ReconnectInitialDelayMs),
                ReconnectMaxDelayMs = PositiveOrFallback(config.ReconnectMaxDelayMs, existing.ReconnectMaxDelayMs),
                ReconnectJitterMs = PositiveOrFallback(config.ReconnectJitterMs, existing.ReconnectJitterMs),
                EnvironmentTags = config.EnvironmentTags?.Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x.Trim()).Distinct().ToList()
                    ?? existing.EnvironmentTags
            };

            _snapshot = _snapshot with
            {
                Configuration = _snapshot.Configuration with { Transport = normalized }
            };

            AddActivityLocked(ActivitySeverity.Info, "ui", "Transport config saved", $"Endpoint set to {normalized.Endpoint}.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void SaveSecurityConfig(SecurityConfig config)
    {
        lock (_gate)
        {
            var existing = _snapshot.Configuration.Security;
            var gates = existing.PolicyGates;
            var allowUserExit = gates.CanEditAllowUserExit ? config.AllowUserExit : existing.AllowUserExit;

            var normalized = config with
            {
                KernelGuardTag = string.IsNullOrWhiteSpace(config.KernelGuardTag) ? existing.KernelGuardTag : config.KernelGuardTag.Trim(),
                RequireCommandSignatureTag = string.IsNullOrWhiteSpace(config.RequireCommandSignatureTag) ? existing.RequireCommandSignatureTag : config.RequireCommandSignatureTag.Trim(),
                RequireKernelSignatureTag = string.IsNullOrWhiteSpace(config.RequireKernelSignatureTag) ? existing.RequireKernelSignatureTag : config.RequireKernelSignatureTag.Trim(),
                SigningAlgorithm = string.IsNullOrWhiteSpace(config.SigningAlgorithm) ? existing.SigningAlgorithm : config.SigningAlgorithm.Trim(),
                AllowUserExit = allowUserExit,
                PolicyGates = gates
            };

            _snapshot = _snapshot with
            {
                Configuration = _snapshot.Configuration with { Security = normalized }
            };

            RefreshLegacySettingsFromConfigurationLocked();
            AddActivityLocked(ActivitySeverity.Info, "ui", "Security policy saved", "Security toggles were updated.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void SaveTelemetryPolicy(TelemetryPolicyConfig config)
    {
        lock (_gate)
        {
            var existing = _snapshot.Configuration.TelemetryPolicy;
            var normalized = config with
            {
                TelemetryIntervalSeconds = PositiveOrFallback(config.TelemetryIntervalSeconds, existing.TelemetryIntervalSeconds),
                HeartbeatIntervalSeconds = PositiveOrFallback(config.HeartbeatIntervalSeconds, existing.HeartbeatIntervalSeconds),
                CpuScopeLabel = string.IsNullOrWhiteSpace(config.CpuScopeLabel) ? existing.CpuScopeLabel : config.CpuScopeLabel.Trim(),
                RamScopeLabel = string.IsNullOrWhiteSpace(config.RamScopeLabel) ? existing.RamScopeLabel : config.RamScopeLabel.Trim(),
                DiskScopeLabel = string.IsNullOrWhiteSpace(config.DiskScopeLabel) ? existing.DiskScopeLabel : config.DiskScopeLabel.Trim(),
                NetworkScopeLabel = string.IsNullOrWhiteSpace(config.NetworkScopeLabel) ? existing.NetworkScopeLabel : config.NetworkScopeLabel.Trim(),
                KernelScopeLabel = string.IsNullOrWhiteSpace(config.KernelScopeLabel) ? existing.KernelScopeLabel : config.KernelScopeLabel.Trim()
            };

            _snapshot = _snapshot with
            {
                Configuration = _snapshot.Configuration with { TelemetryPolicy = normalized }
            };

            AddActivityLocked(ActivitySeverity.Info, "ui", "Telemetry policy saved", "Telemetry intervals and scopes were updated.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void SaveNotificationConfig(NotificationPolicyConfig config)
    {
        lock (_gate)
        {
            var existing = _snapshot.Configuration.Notifications;
            var normalized = config with
            {
                ReconnectWarningThresholdSeconds = PositiveOrFallback(config.ReconnectWarningThresholdSeconds, existing.ReconnectWarningThresholdSeconds),
                RateLimitWindowMinutes = PositiveOrFallback(config.RateLimitWindowMinutes, existing.RateLimitWindowMinutes)
            };

            _snapshot = _snapshot with
            {
                Configuration = _snapshot.Configuration with { Notifications = normalized }
            };

            RefreshLegacySettingsFromConfigurationLocked();
            AddActivityLocked(ActivitySeverity.Info, "ui", "Notification policy saved", "Notification rules were updated.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void TestTransportConnection()
    {
        lock (_gate)
        {
            var now = DateTimeOffset.UtcNow;
            var latency = _random.Next(26, 110);

            _snapshot = _snapshot with
            {
                LastSyncUtc = now,
                LastHeartbeatUtc = now,
                LatencyMs = latency,
                Connection = ConnectionState.Connected,
                CurrentActivity = "Transport test succeeded"
            };

            AddActivityLocked(ActivitySeverity.Info, "transport", "Transport test OK", $"Endpoint {_snapshot.Configuration.Transport.Endpoint} responded in {latency} ms.");
            RebuildDeviceFactsLocked(now);
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
            _onboardingOperationId += 1;
            var preservedSettings = _snapshot.Settings;
            var preservedHistory = _snapshot.CommandHistory;
            var preservedConfiguration = _snapshot.Configuration;
            var nextActivity = _snapshot.Activity.ToList();
            nextActivity.Insert(0, new ActivityEntry(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "ui", "Re-pair started", "Device was moved back to onboarding state."));

            _snapshot = AgentStateSnapshot.CreateInitial() with
            {
                Settings = preservedSettings,
                CommandHistory = preservedHistory,
                Configuration = preservedConfiguration,
                Activity = nextActivity.Take(80).ToList(),
                CurrentActivity = "Waiting for re-pairing"
            };

            SyncConfigurationIdentityLocked();
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    public void ResetUiSession()
    {
        lock (_gate)
        {
            _reconnectHoldTicks = 0;
            _onboardingOperationId = 0;
            _snapshot = AgentStateSnapshot.CreateInitial();
            RefreshLegacySettingsFromConfigurationLocked();
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    private async Task SimulateDetectResultAsync(int operationId)
    {
        await Task.Delay(900).ConfigureAwait(false);
        lock (_gate)
        {
            if (operationId != _onboardingOperationId || _snapshot.IsPaired)
            {
                return;
            }

            _snapshot = _snapshot with
            {
                Onboarding = _snapshot.Onboarding with
                {
                    Stage = OnboardingStage.Detect,
                    DetectState = OnboardingDetectState.NotEnrolled
                },
                CurrentActivity = "Device not enrolled"
            };
            AddActivityLocked(ActivitySeverity.Warning, "service", "Enrollment check complete", "No active enrollment found for this device.");
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    private async Task SimulateTokenVerificationAsync(int operationId, string token)
    {
        await Task.Delay(1200).ConfigureAwait(false);
        bool success;
        lock (_gate)
        {
            if (operationId != _onboardingOperationId || _snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            success = string.Equals(token, ExpectedPairCode, StringComparison.Ordinal);
            if (!success)
            {
                _snapshot = _snapshot with
                {
                    Onboarding = _snapshot.Onboarding with
                    {
                        Stage = OnboardingStage.Pair,
                        PairMode = OnboardingPairMode.Token,
                        PairState = OnboardingPairState.TokenFailed,
                        PairError = "Invalid pairing code. Please retry.",
                        TokenDigits = string.Empty
                    },
                    CurrentActivity = "Pair code verification failed"
                };
                AddActivityLocked(ActivitySeverity.Warning, "service", "Pair code rejected", "Token verification failed in UI-only mode.");
                RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
            }
            else
            {
                BeginConfirmRegistrationLocked("Token verified. Registering device.");
            }
        }

        Publish(Snapshot);

        if (success)
        {
            await SimulateRegistrationAsync(operationId).ConfigureAwait(false);
        }
    }

    private async Task SimulateQrPairingAsync(int operationId)
    {
        await Task.Delay(2000).ConfigureAwait(false);
        lock (_gate)
        {
            if (operationId != _onboardingOperationId || _snapshot.IsPaired || _snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return;
            }

            BeginConfirmRegistrationLocked("QR scan confirmed. Registering device.");
        }

        Publish(Snapshot);
        await SimulateRegistrationAsync(operationId).ConfigureAwait(false);
    }

    private async Task SimulateRegistrationAsync(int operationId)
    {
        await Task.Delay(1300).ConfigureAwait(false);
        lock (_gate)
        {
            if (operationId != _onboardingOperationId || _snapshot.Onboarding.Stage != OnboardingStage.Confirm)
            {
                return;
            }

            ApplyEnrollmentCompleteLocked(DateTimeOffset.UtcNow);
            RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
        }

        Publish(Snapshot);
    }

    private void BeginConfirmRegistrationLocked(string activity)
    {
        _snapshot = _snapshot with
        {
            Onboarding = _snapshot.Onboarding with
            {
                Stage = OnboardingStage.Confirm,
                PairState = OnboardingPairState.PairSucceeded,
                ConfirmState = OnboardingConfirmState.Registering,
                PairError = string.Empty
            },
            CurrentActivity = activity
        };
        AddActivityLocked(ActivitySeverity.Info, "service", "Pairing accepted", "Pairing was accepted, awaiting registration completion.");
        RebuildDeviceFactsLocked(DateTimeOffset.UtcNow);
    }

    private void ApplyEnrollmentCompleteLocked(DateTimeOffset now)
    {
        _snapshot = _snapshot with
        {
            IsPaired = true,
            DeviceId = MockDeviceId,
            DeviceName = MockDeviceName,
            PolicyHash = MockPolicyHash,
            Connection = ConnectionState.Connected,
            Health = HealthState.Healthy,
            CurrentActivity = "Connected and monitoring",
            LastSyncUtc = now,
            LastHeartbeatUtc = now,
            ReconnectAttempts = 0,
            Onboarding = _snapshot.Onboarding with
            {
                Stage = OnboardingStage.Confirm,
                ConfirmState = OnboardingConfirmState.EnrollmentComplete,
                EnrolledAtUtc = now,
                PairError = string.Empty
            }
        };

        var enrolledIdentity = AgentConfiguration.CreateDefault(
            now,
            deviceId: _snapshot.DeviceId,
            deviceName: _snapshot.DeviceName,
            agentVersion: _snapshot.AgentVersion,
            isEnrolled: true).DeviceIdentity;

        _snapshot = _snapshot with
        {
            Configuration = _snapshot.Configuration with
            {
                DeviceIdentity = enrolledIdentity
            }
        };

        SyncConfigurationIdentityLocked();
        RefreshLegacySettingsFromConfigurationLocked();
        AddActivityLocked(ActivitySeverity.Info, "service", "Enrollment complete", "Device registered and paired successfully.");
    }

    private string BuildPairingStringLocked()
    {
        var payload = new Dictionary<string, object?>
        {
            ["type"] = "quoodle_pair",
            ["version"] = 1,
            ["device_id"] = _snapshot.DeviceId,
            ["pair_token"] = $"mock-pair-{ExpectedPairCode}",
            ["pair_session_id"] = $"sess-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}",
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O"),
            ["controller_url"] = "https://control.quoodle.local",
            ["device_label"] = _snapshot.DeviceName
        };

        return JsonSerializer.Serialize(payload);
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
                var idleMessage = _snapshot.Onboarding.Stage switch
                {
                    OnboardingStage.Detect when _snapshot.Onboarding.DetectState == OnboardingDetectState.Checking => "Checking enrollment status",
                    OnboardingStage.Detect => "Waiting for pairing",
                    OnboardingStage.Pair when _snapshot.Onboarding.PairMode == OnboardingPairMode.Qr => "Waiting for QR scan confirmation",
                    OnboardingStage.Pair => "Awaiting pair code or QR scan",
                    OnboardingStage.Confirm when _snapshot.Onboarding.ConfirmState == OnboardingConfirmState.Registering => "Registering device enrollment",
                    OnboardingStage.Confirm => "Enrollment complete",
                    _ => "Waiting for pairing"
                };

                _snapshot = _snapshot with
                {
                    LastHeartbeatUtc = now,
                    CurrentActivity = idleMessage
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
        SyncConfigurationIdentityLocked();

        var facts = new List<DeviceFact>
        {
            new("Identity", "Device Name", _snapshot.DeviceName),
            new("Identity", "Device ID", _snapshot.DeviceId),
            new("Identity", "Agent Version", _snapshot.AgentVersion),
            new("Identity", "Policy Hash", _snapshot.PolicyHash),
            new("Runtime", "Pairing State", _snapshot.IsPaired ? "Paired" : "Not paired"),
            new("Runtime", "Connection", _snapshot.Connection.ToString()),
            new("Runtime", "Current Activity", _snapshot.CurrentActivity),
            new("Network", "Latency", $"{_snapshot.LatencyMs} ms"),
            new("Network", "RX/TX", $"{_snapshot.NetworkRxMbps:F2} / {_snapshot.NetworkTxMbps:F2} Mbps"),
            new("Sync/Health", "Health", _snapshot.Health.ToString()),
            new("Sync/Health", "CPU / Memory / Disk", $"{_snapshot.CpuPercent}% / {_snapshot.MemoryPercent}% / {_snapshot.DiskPercent}%"),
            new("Sync/Health", "Last Heartbeat", _snapshot.LastHeartbeatUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")),
            new("Sync/Health", "Last Sync", _snapshot.LastSyncUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")),
            new("Sync/Health", "Enrolled At", _snapshot.Onboarding.EnrolledAtUtc?.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss") ?? "Pending"),
            new("Sync/Health", "Snapshot Updated", now.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"))
        };

        _snapshot = _snapshot with { DeviceFacts = facts };
        RebuildDiagnosticsRowsLocked(now);
    }

    private void SyncConfigurationIdentityLocked()
    {
        var identity = _snapshot.Configuration.DeviceIdentity with
        {
            DeviceId = _snapshot.DeviceId,
            AgentVersion = $"v{_snapshot.AgentVersion}",
            OsBuild = Environment.OSVersion.VersionString.Replace("Microsoft Windows", "Windows").Trim(),
            EnrolledAtUtc = _snapshot.Onboarding.EnrolledAtUtc ?? _snapshot.Configuration.DeviceIdentity.EnrolledAtUtc,
            EnrolledState = _snapshot.IsPaired ? "Enrolled" : "Not Enrolled"
        };

        if (!_snapshot.IsPaired)
        {
            identity = identity with { EnrolledAtUtc = null };
        }

        if (string.IsNullOrWhiteSpace(identity.EnrolledAccount))
        {
            identity = identity with
            {
                EnrolledAccount = _snapshot.IsPaired ? "operator@corp.quoodle.io" : "pending@quoodle.local"
            };
        }

        if (string.IsNullOrWhiteSpace(identity.LocalStoragePath))
        {
            identity = identity with
            {
                LocalStoragePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                    "Quoodle",
                    "device_id")
            };
        }

        var configuration = _snapshot.Configuration with { DeviceIdentity = identity };
        _snapshot = _snapshot with { Configuration = configuration };
    }

    private void RebuildDiagnosticsRowsLocked(DateTimeOffset now)
    {
        var commandRows = BuildCommandRowsLocked();
        var kernelRows = BuildKernelRowsLocked(now, commandRows);
        var wssRows = BuildWssRowsLocked(now, commandRows);

        _snapshot = _snapshot with
        {
            WssMessageLog = wssRows,
            CommandHistoryLog = commandRows,
            KernelEvents = kernelRows
        };
    }

    private IReadOnlyList<CommandHistoryRow> BuildCommandRowsLocked()
    {
        if (_snapshot.CommandHistory.Count == 0)
        {
            return Array.Empty<CommandHistoryRow>();
        }

        return _snapshot.CommandHistory
            .OrderByDescending(x => x.IssuedAtUtc)
            .Take(47)
            .Select((entry, index) =>
            {
                var priority = index % 9 == 0 || entry.Command.Contains("lock", StringComparison.OrdinalIgnoreCase)
                    ? "high"
                    : "normal";

                var state = entry.Status switch
                {
                    CommandExecutionStatus.Succeeded => "completed",
                    CommandExecutionStatus.Failed => "failed",
                    CommandExecutionStatus.Rejected => "rejected",
                    CommandExecutionStatus.TimedOut => "timed_out",
                    CommandExecutionStatus.Executing => "running",
                    CommandExecutionStatus.Dispatched => "dispatched",
                    _ => "queued"
                };

                var execPath = entry.Source == "scheduler" ? "_. Named Pipe" : ">. IOCTL";
                var kexec = $"kexec-{Math.Abs(entry.Id.GetHashCode()) % 1000:000}";
                var originUser = entry.Source switch
                {
                    "control-plane" => "UID001",
                    "scheduler" => "UID002",
                    _ => "UID003"
                };

                var raw = JsonSerializer.Serialize(new
                {
                    command_message_id = entry.Id.ToUpperInvariant(),
                    method = entry.Command.Replace('.', '_'),
                    execution_state = state,
                    priority,
                    result = new
                    {
                        status = entry.Status == CommandExecutionStatus.Succeeded ? "ok" : "error"
                    },
                    error_code = string.IsNullOrWhiteSpace(entry.ErrorMessage) ? null : "E-MOCK-4004",
                    kernel_exec_id = kexec,
                    issued_at = entry.IssuedAtUtc
                }, JsonPretty);

                return new CommandHistoryRow(
                    CommandId: entry.Id.ToUpperInvariant(),
                    Method: entry.Command.Replace('.', '_'),
                    Priority: priority,
                    State: state,
                    ExecPath: execPath,
                    KernelExecId: kexec,
                    IssuedAt: entry.IssuedAtUtc,
                    DurationMs: entry.DurationMs > 0 ? entry.DurationMs : null,
                    OriginUser: originUser,
                    RawJson: raw);
            })
            .ToList();
    }

    private static IReadOnlyList<KernelEventRow> BuildKernelRowsLocked(DateTimeOffset now, IReadOnlyList<CommandHistoryRow> commandRows)
    {
        if (commandRows.Count == 0)
        {
            return Array.Empty<KernelEventRow>();
        }

        var rows = new List<KernelEventRow>(14);
        for (var i = 0; i < 14; i++)
        {
            var source = commandRows[i % commandRows.Count];
            var eventId = 14 - i;
            var eventType = i % 5 == 0 ? 2 : 1;
            var opcode = source.Method?.Contains("lock", StringComparison.OrdinalIgnoreCase) == true
                ? "SHUTDOWN"
                : i % 4 == 0 ? "REBOOT" : "PING";
            var status = i % 3 == 1 ? "not_supported" : "ok";
            var errorCode = status == "ok" ? 0 : 4004;
            var timestamp = source.IssuedAt ?? now.AddMinutes(-(i + 1) * 7);
            var agentSeq = 114 - i;
            var kexec = source.KernelExecId ?? $"kexec-{eventId:000}";
            var commandId = source.CommandId ?? "-";

            var raw = JsonSerializer.Serialize(new
            {
                event_id = eventId,
                event_type = eventType,
                timestamp_unix = timestamp.ToUnixTimeSeconds(),
                payload_json = JsonSerializer.Serialize(new
                {
                    opcode,
                    status,
                    error_code = errorCode
                }),
                request_id = $"req-{eventId:000}",
                kernel_exec_id = kexec
            }, JsonPretty);

            rows.Add(new KernelEventRow(
                EventId: eventId,
                EventType: eventType,
                Opcode: opcode,
                Status: status,
                ErrorCode: errorCode,
                KernelExecId: kexec,
                AgentSeq: agentSeq,
                CommandId: commandId,
                Timestamp: timestamp,
                RawJson: raw));
        }

        return rows;
    }

    private IReadOnlyList<WssMessageLogRow> BuildWssRowsLocked(DateTimeOffset now, IReadOnlyList<CommandHistoryRow> commandRows)
    {
        var rows = new List<WssMessageLogRow>(82);

        for (var seq = 82; seq >= 1; seq--)
        {
            var type = ResolveWssType(seq);
            var from = type is "COMMAND_DELIVERY" or "COMMAND_ACK" ? "controller" : "agent";
            var messageId = $"m-{type.ToLowerInvariant().Replace("_", "-")[..Math.Min(6, type.Length)]}-{seq:000}";
            var timestamp = now.AddSeconds(-(82 - seq) * 42);

            var command = commandRows.Count > 0 ? commandRows[(82 - seq) % commandRows.Count] : null;
            var bodySummary = type switch
            {
                "HEARTBEAT" => $"status=alive uptime={12000 + seq}s error_state=ok",
                "TELEMETRY" => $"scope=telemetry_basic cpu={_snapshot.CpuPercent}% ram={_snapshot.MemoryPercent}% disk={_snapshot.DiskPercent}%",
                "KERNEL_EVENT" => $"scope=kernel_event event_id={seq % 15} event_type={(seq % 2) + 1} opcode=PING",
                "COMMAND_RESULT" => $"{command?.CommandId ?? "CMD-0000"} {command?.Method ?? "health_sample"} execution_state={command?.State ?? "completed"}",
                "COMMAND_ACK" => $"{command?.CommandId ?? "CMD-0000"} status=received reason=null",
                _ => $"{command?.CommandId ?? "CMD-0000"} method={command?.Method ?? "ping"} priority={command?.Priority ?? "normal"} TTL=300s"
            };

            var sigState = type == "COMMAND_RESULT" && seq % 14 == 0 ? "not_ok" : "ok";
            var raw = JsonSerializer.Serialize(new
            {
                type,
                from,
                device_id = _snapshot.DeviceId,
                seq,
                timestamp,
                body = new
                {
                    message_id = command?.CommandId ?? messageId.ToUpperInvariant(),
                    summary = bodySummary,
                    sig = sigState
                }
            }, JsonPretty);

            rows.Add(new WssMessageLogRow(
                Sequence: seq,
                Type: type,
                From: from,
                MessageId: messageId,
                Timestamp: timestamp,
                BodySummary: bodySummary,
                SigState: sigState,
                RawJson: raw));
        }

        return rows;
    }

    private static string ResolveWssType(int seq)
    {
        if (seq % 13 == 0) return "COMMAND_ACK";
        if (seq % 11 == 0) return "COMMAND_DELIVERY";
        if (seq % 7 == 0) return "COMMAND_RESULT";
        if (seq % 5 == 0) return "TELEMETRY";
        if (seq % 3 == 0) return "KERNEL_EVENT";
        return "HEARTBEAT";
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

    private void RefreshLegacySettingsFromConfigurationLocked()
    {
        var notifications = _snapshot.Configuration.Notifications;
        var security = _snapshot.Configuration.Security;
        var current = _snapshot.Settings;

        var notifyInfo = notifications.NotifyConnectionRecovered
            || notifications.NotifyKernelEventReceived
            || notifications.NotifyCommandCompletedSuccessfully;

        var notifyWarningsAndCritical = notifications.NotifyCommandExecutionFailed
            || notifications.NotifyAuthFailed
            || notifications.NotifyPolicyHashMismatch
            || notifications.NotifyConnectionDegraded;

        _snapshot = _snapshot with
        {
            Settings = current with
            {
                NotifyInfo = notifyInfo,
                NotifyWarningsAndCritical = notifyWarningsAndCritical,
                CollectDiagnostics = security.KernelGuardEnabled
            }
        };
    }

    private static int PositiveOrFallback(int value, int fallback) => value > 0 ? value : fallback;

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
