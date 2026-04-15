using System.ComponentModel;
using System.IO.Pipes;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;
using System.Threading;
using Microsoft.Win32;
using Quoodle.Agent.UiCompanion.Models;

namespace Quoodle.Agent.UiCompanion.Services;

public sealed class UiBridgeProvider : IAgentStateProvider
{
    private const string ServiceName = "QuoodleAgent";
    private const string DeviceIdPath = @"C:\ProgramData\Quoodle\device_id";
    private const string AgentJwtPath = @"C:\ProgramData\Quoodle\agent_jwt";
    private const string AgentEndpointPath = @"C:\ProgramData\Quoodle\agent_endpoint";
    private const string AgentPubkeyPath = @"C:\ProgramData\Quoodle\agent_pubkey";
    private const string UiBridgePipeName = "QuoodleAgentUiBridge";
    private const int PipeTimeoutMs = 1200;
    private const int PairingPollMaxAttempts = 90;
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(3);

    private readonly object _gate = new();
    private readonly MockAgentStateProvider _fallbackProvider = new();
    private readonly List<ActivityEntry> _bridgeActivity = new();
    private readonly Timer _pollTimer;
    private readonly HttpClient _pairingHttp;
    private readonly string _controlPlaneBaseUrl;

    private AgentStateSnapshot _baseSnapshot = AgentStateSnapshot.CreateInitial();
    private AgentStateSnapshot _snapshot = AgentStateSnapshot.CreateInitial();
    private bool _started;
    private bool _disposed;
    private bool _lastServiceInstalled;
    private string _lastServiceStatus = string.Empty;
    private string _lastDeviceId = string.Empty;
    private int _onboardingOperationId;
    private string _pendingPairToken = string.Empty;
    private string _pendingPairSessionId = string.Empty;
    private string _pendingPairDeviceId = string.Empty;
    private string _lastRuntimeAgentPubkey = string.Empty;

    public UiBridgeProvider()
    {
        _pollTimer = new Timer(_ => PollRuntime(), null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        _controlPlaneBaseUrl = ResolveControlPlaneBaseUrl();
        _pairingHttp = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(12)
        };

        _fallbackProvider.SnapshotChanged += HandleFallbackSnapshotChanged;
        _baseSnapshot = _fallbackProvider.Snapshot;
        _snapshot = MergeSnapshot(_baseSnapshot, RuntimeProbeSnapshot());

        AddBridgeActivity(
            DateTimeOffset.UtcNow,
            ActivitySeverity.Info,
            "Pairing endpoint configured",
            $"Control plane base URL set to {_controlPlaneBaseUrl}.");
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
        private set
        {
            lock (_gate)
            {
                _snapshot = value;
            }
        }
    }

    public event EventHandler<AgentStateSnapshot>? SnapshotChanged;

    public void Start()
    {
        if (_disposed)
        {
            return;
        }

        lock (_gate)
        {
            if (_started)
            {
                return;
            }
            _started = true;
        }

        _pollTimer.Change(TimeSpan.Zero, PollInterval);
        Publish(Snapshot);
    }

    public void Stop()
    {
        lock (_gate)
        {
            if (!_started)
            {
                return;
            }
            _started = false;
        }

        _pollTimer.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    public void CheckEnrollmentStatus()
    {
        var operationId = NextOnboardingOperationId();
        UpdateBaseline(snapshot => snapshot with
        {
            Onboarding = snapshot.Onboarding with
            {
                Stage = OnboardingStage.Detect,
                DetectState = OnboardingDetectState.Checking,
                PairError = string.Empty
            },
            CurrentActivity = "Checking enrollment status"
        });

        _ = CompleteEnrollmentProbeAsync(operationId);
    }

    public void BeginPairing()
    {
        var operationId = NextOnboardingOperationId();
        ClearPendingPairingData();

        UpdateBaseline(snapshot => snapshot with
        {
            IsPaired = false,
            Onboarding = snapshot.Onboarding with
            {
                Stage = OnboardingStage.Pair,
                DetectState = OnboardingDetectState.NotEnrolled,
                PairMode = OnboardingPairMode.Token,
                PairState = OnboardingPairState.TokenEntry,
                ConfirmState = OnboardingConfirmState.Registering,
                TokenDigits = string.Empty,
                PairingString = string.Empty,
                PairError = string.Empty,
                EnrolledAtUtc = null
            },
            CurrentActivity = "Requesting pairing token"
        });

        _ = RequestPairingTokenAsync(operationId);
    }

    public void SelectPairMode(OnboardingPairMode mode)
    {
        UpdateBaseline(snapshot =>
        {
            if (snapshot.IsPaired || snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return snapshot;
            }

            return snapshot with
            {
                Onboarding = snapshot.Onboarding with
                {
                    PairMode = mode,
                    PairState = mode == OnboardingPairMode.Qr
                        ? OnboardingPairState.QrWaiting
                        : OnboardingPairState.TokenEntry,
                    PairError = string.Empty
                },
                CurrentActivity = mode == OnboardingPairMode.Qr
                    ? "Waiting for mobile app scan"
                    : "Awaiting pair code confirmation"
            };
        });
    }

    public void SetPairTokenDigits(string tokenDigits)
    {
        UpdateBaseline(snapshot =>
        {
            if (snapshot.IsPaired || snapshot.Onboarding.Stage != OnboardingStage.Pair)
            {
                return snapshot;
            }

            var sanitized = new string((tokenDigits ?? string.Empty).Where(char.IsDigit).Take(6).ToArray());
            var pairState = snapshot.Onboarding.PairState == OnboardingPairState.TokenVerifying
                ? OnboardingPairState.TokenVerifying
                : OnboardingPairState.TokenEntry;

            return snapshot with
            {
                Onboarding = snapshot.Onboarding with
                {
                    PairMode = OnboardingPairMode.Token,
                    PairState = pairState,
                    TokenDigits = sanitized,
                    PairError = string.Empty
                }
            };
        });
    }

    public void VerifyTokenPairing()
    {
        string pairToken;
        var operationId = NextOnboardingOperationId();
        lock (_gate)
        {
            pairToken = _pendingPairToken;
        }

        if (string.IsNullOrWhiteSpace(pairToken))
        {
            UpdateBaseline(snapshot => snapshot with
            {
                Onboarding = snapshot.Onboarding with
                {
                    PairMode = OnboardingPairMode.Token,
                    PairState = OnboardingPairState.TokenFailed,
                    PairError = "No active pair token yet. Use QR mode to request one first."
                },
                CurrentActivity = "Token pairing unavailable"
            });
            return;
        }

        UpdateBaseline(snapshot => snapshot with
        {
            Onboarding = snapshot.Onboarding with
            {
                PairMode = OnboardingPairMode.Token,
                PairState = OnboardingPairState.TokenVerifying,
                PairError = string.Empty
            },
            CurrentActivity = "Waiting for mobile confirmation"
        });

        _ = WaitForPairConfirmationAsync(operationId, preferQrState: false);
    }

    public void StartQrPairing()
    {
        var operationId = NextOnboardingOperationId();
        UpdateBaseline(snapshot => snapshot with
        {
            Onboarding = snapshot.Onboarding with
            {
                Stage = OnboardingStage.Pair,
                DetectState = OnboardingDetectState.NotEnrolled,
                PairMode = OnboardingPairMode.Qr,
                PairState = OnboardingPairState.QrWaiting,
                PairError = string.Empty
            },
            CurrentActivity = "Generating QR pairing payload"
        });

        bool hasPendingToken;
        lock (_gate)
        {
            hasPendingToken = !string.IsNullOrWhiteSpace(_pendingPairToken);
        }

        if (!hasPendingToken)
        {
            _ = RequestPairingTokenAsync(operationId);
            return;
        }

        _ = WaitForPairConfirmationAsync(operationId, preferQrState: true);
    }

    public void RetryPairing()
    {
        _ = NextOnboardingOperationId();
        ClearPendingPairingData();
        UpdateBaseline(snapshot => snapshot with
        {
            Onboarding = snapshot.Onboarding with
            {
                Stage = OnboardingStage.Pair,
                PairMode = OnboardingPairMode.Token,
                PairState = OnboardingPairState.TokenEntry,
                TokenDigits = string.Empty,
                PairError = string.Empty
            },
            CurrentActivity = "Retry pairing"
        });
    }

    public void CompleteEnrollment()
    {
        UpdateBaseline(snapshot =>
        {
            if (snapshot.Onboarding.Stage != OnboardingStage.Confirm)
            {
                return snapshot;
            }

            var now = DateTimeOffset.UtcNow;
            return snapshot with
            {
                IsPaired = true,
                Onboarding = snapshot.Onboarding with
                {
                    ConfirmState = OnboardingConfirmState.EnrollmentComplete,
                    EnrolledAtUtc = snapshot.Onboarding.EnrolledAtUtc ?? now,
                    PairError = string.Empty
                },
                CurrentActivity = "Enrollment complete"
            };
        });
    }

    public void TriggerSyncNow()
    {
        if (TrySendPipeCommand("sync_now", out var reason))
        {
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Info, "Sync requested", "sync_now sent to agent runtime.");
        }
        else
        {
            _fallbackProvider.TriggerSyncNow();
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Sync fallback", $"sync_now RPC failed ({reason}); fallback provider updated local state.");
        }

        PollRuntime();
    }

    public void UpdateSettings(UiSettings settings) => _fallbackProvider.UpdateSettings(settings);

    public void SaveTransportConfig(TransportConfig config)
    {
        _fallbackProvider.SaveTransportConfig(config);
        if (!string.IsNullOrWhiteSpace(config.Endpoint))
        {
            if (TryWriteRuntimeValue(AgentEndpointPath, config.Endpoint.Trim()))
            {
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Info, "Endpoint persisted", $"Saved endpoint to {AgentEndpointPath}.");
            }
            else
            {
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Endpoint persist failed", $"Could not write endpoint to {AgentEndpointPath}.");
            }
        }
    }

    public void SaveSecurityConfig(SecurityConfig config) => _fallbackProvider.SaveSecurityConfig(config);

    public void SaveTelemetryPolicy(TelemetryPolicyConfig config) => _fallbackProvider.SaveTelemetryPolicy(config);

    public void SaveNotificationConfig(NotificationPolicyConfig config) => _fallbackProvider.SaveNotificationConfig(config);

    public void TestTransportConnection()
    {
        if (TrySendPipeCommand("sync_now", out _))
        {
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Info, "Transport test", "Status ping sent to agent runtime via pipe.");
        }
        else
        {
            _fallbackProvider.TestTransportConnection();
        }
        PollRuntime();
    }

    public void RetryConnection()
    {
        if (TrySendPipeCommand("reconnect", out var reason))
        {
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Reconnect requested", "reconnect sent to agent runtime.");
        }
        else
        {
            _fallbackProvider.RetryConnection();
            TryStartService();
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Reconnect fallback", $"reconnect RPC failed ({reason}); attempted SCM start/retry.");
        }

        PollRuntime();
    }

    public void BeginRePairFlow()
    {
        _ = NextOnboardingOperationId();
        ClearPendingPairingData();

        UpdateBaseline(snapshot => snapshot with
        {
            IsPaired = false,
            Onboarding = snapshot.Onboarding with
            {
                Stage = OnboardingStage.Detect,
                DetectState = OnboardingDetectState.NotEnrolled,
                PairMode = OnboardingPairMode.Token,
                PairState = OnboardingPairState.TokenEntry,
                ConfirmState = OnboardingConfirmState.Registering,
                PairingString = string.Empty,
                PairError = string.Empty,
                TokenDigits = string.Empty,
                EnrolledAtUtc = null
            },
            CurrentActivity = "Re-pair flow started",
            Configuration = snapshot.Configuration with
            {
                DeviceIdentity = snapshot.Configuration.DeviceIdentity with
                {
                    EnrolledState = "Not Enrolled",
                    EnrolledAtUtc = null
                }
            }
        });

        AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Re-pair requested", "Device marked for re-pairing in UI state.");
    }

    public void ResetUiSession()
    {
        _ = NextOnboardingOperationId();
        ClearPendingPairingData();
        UpdateBaseline(snapshot => snapshot with
        {
            Onboarding = OnboardingFlowState.CreateInitial(),
            CurrentActivity = "UI session reset"
        });
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;

        Stop();
        _fallbackProvider.SnapshotChanged -= HandleFallbackSnapshotChanged;
        _fallbackProvider.Dispose();
        _pairingHttp.Dispose();
        _pollTimer.Dispose();
    }

    private void HandleFallbackSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        RuntimeProbe probe;
        AgentStateSnapshot merged;
        lock (_gate)
        {
            var preserved = _baseSnapshot;
            var preservedIdentity = preserved.Configuration.DeviceIdentity;
            var mergedIdentity = snapshot.Configuration.DeviceIdentity with
            {
                DeviceId = string.IsNullOrWhiteSpace(preservedIdentity.DeviceId) ? snapshot.Configuration.DeviceIdentity.DeviceId : preservedIdentity.DeviceId,
                EnrolledState = preservedIdentity.EnrolledState,
                EnrolledAtUtc = preservedIdentity.EnrolledAtUtc
            };

            _baseSnapshot = snapshot with
            {
                IsPaired = preserved.IsPaired,
                Onboarding = preserved.Onboarding,
                DeviceId = string.IsNullOrWhiteSpace(preserved.DeviceId) ? snapshot.DeviceId : preserved.DeviceId,
                DeviceName = string.IsNullOrWhiteSpace(preserved.DeviceName) ? snapshot.DeviceName : preserved.DeviceName,
                CurrentActivity = string.IsNullOrWhiteSpace(preserved.CurrentActivity) ? snapshot.CurrentActivity : preserved.CurrentActivity,
                Configuration = snapshot.Configuration with
                {
                    DeviceIdentity = mergedIdentity
                }
            };

            probe = RuntimeProbeSnapshot();
            merged = MergeSnapshot(_baseSnapshot, probe);
            _snapshot = merged;
        }
        SnapshotChanged?.Invoke(this, merged);
    }

    private void PollRuntime()
    {
        if (_disposed)
        {
            return;
        }

        AgentStateSnapshot merged;
        lock (_gate)
        {
            var probe = RuntimeProbeSnapshot();
            merged = MergeSnapshot(_baseSnapshot, probe);
            _snapshot = merged;
        }
        SnapshotChanged?.Invoke(this, merged);
    }

    private RuntimeProbe RuntimeProbeSnapshot()
    {
        var now = DateTimeOffset.UtcNow;
        if (TryProbeViaPipe(out var pipeStatus))
        {
            AppendBridgeActivityIfChanged(now, true, pipeStatus.ServiceStatusLabel, pipeStatus.DeviceId);
            return new RuntimeProbe(
                now,
                true,
                pipeStatus.ServiceStatusLabel,
                pipeStatus.Connection,
                true,
                pipeStatus.DeviceId,
                !string.IsNullOrWhiteSpace(pipeStatus.DeviceId),
                pipeStatus.ReconnectAttempts,
                pipeStatus.Endpoint,
                pipeStatus.AgentPubkey);
        }

        var deviceId = ReadDeviceId();
        var (installed, status, statusLabel) = QueryServiceStatus();
        var connection = MapConnection(status);
        var running = status == ServiceControllerStatus.Running;

        AppendBridgeActivityIfChanged(now, installed, statusLabel, deviceId);

        return new RuntimeProbe(
            now,
            installed,
            statusLabel,
            connection,
            running,
            deviceId,
            !string.IsNullOrWhiteSpace(deviceId),
            0,
            string.Empty,
            ReadRuntimeValue(AgentPubkeyPath));
    }

    private AgentStateSnapshot MergeSnapshot(AgentStateSnapshot baseline, RuntimeProbe probe)
    {
        var effectiveDeviceId = string.IsNullOrWhiteSpace(probe.DeviceId) ? baseline.DeviceId : probe.DeviceId;
        var isPaired = probe.IsPaired || baseline.IsPaired;

        var onboarding = isPaired
            ? baseline.Onboarding with
            {
                Stage = OnboardingStage.Confirm,
                ConfirmState = OnboardingConfirmState.EnrollmentComplete,
                EnrolledAtUtc = baseline.Onboarding.EnrolledAtUtc ?? probe.ObservedAtUtc,
                PairError = string.Empty
            }
            : baseline.Onboarding;

        var health = probe.IsServiceInstalled
            ? (probe.IsServiceRunning ? baseline.Health : HealthState.Warning)
            : HealthState.Critical;

        var activity = MergeActivity(baseline.Activity, _bridgeActivity);

        var facts = BuildDeviceFacts(
            baseline.DeviceFacts,
            effectiveDeviceId,
            isPaired,
            probe.ServiceStatusLabel,
            probe.Connection,
            probe.ObservedAtUtc);

        var updatedIdentity = baseline.Configuration.DeviceIdentity with
        {
            DeviceId = effectiveDeviceId,
            EnrolledState = isPaired ? "Enrolled" : "Not Enrolled",
            EnrolledAtUtc = isPaired ? baseline.Configuration.DeviceIdentity.EnrolledAtUtc ?? probe.ObservedAtUtc : null,
            LocalStoragePath = DeviceIdPath
        };

        var transport = !string.IsNullOrWhiteSpace(probe.Endpoint)
            ? baseline.Configuration.Transport with { Endpoint = probe.Endpoint }
            : baseline.Configuration.Transport;

        var updatedConfig = baseline.Configuration with
        {
            DeviceIdentity = updatedIdentity,
            Transport = transport
        };

        var showOnboardingActivity = !isPaired || onboarding.ConfirmState != OnboardingConfirmState.EnrollmentComplete;
        var activityText = showOnboardingActivity && !string.IsNullOrWhiteSpace(baseline.CurrentActivity)
            ? baseline.CurrentActivity
            : BuildCurrentActivity(probe);

        return baseline with
        {
            IsPaired = isPaired,
            Onboarding = onboarding,
            DeviceId = effectiveDeviceId,
            DeviceName = Environment.MachineName,
            Connection = probe.Connection,
            Health = health,
            LastHeartbeatUtc = probe.IsServiceRunning ? probe.ObservedAtUtc : baseline.LastHeartbeatUtc,
            LastSyncUtc = probe.IsServiceRunning ? probe.ObservedAtUtc : baseline.LastSyncUtc,
            ReconnectAttempts = probe.ReconnectAttempts > 0 ? probe.ReconnectAttempts : baseline.ReconnectAttempts,
            CurrentActivity = activityText,
            Activity = activity,
            DeviceFacts = facts,
            Configuration = updatedConfig
        };
    }

    private static string BuildCurrentActivity(RuntimeProbe probe)
    {
        if (!probe.IsServiceInstalled)
        {
            return "Agent service not installed";
        }

        return probe.Connection switch
        {
            ConnectionState.Connected => "Agent service running",
            ConnectionState.Connecting => "Agent service starting",
            ConnectionState.Reconnecting => "Agent service transitioning",
            ConnectionState.Offline => "Agent service offline",
            ConnectionState.AuthFailed => "Agent service auth failed",
            _ => "Agent service state unknown"
        };
    }

    private static IReadOnlyList<ActivityEntry> MergeActivity(
        IReadOnlyList<ActivityEntry> baseline,
        IReadOnlyList<ActivityEntry> bridgeActivity)
    {
        var merged = new List<ActivityEntry>(bridgeActivity.Count + baseline.Count);
        merged.AddRange(bridgeActivity.OrderByDescending(x => x.Timestamp));
        merged.AddRange(baseline);
        return merged
            .OrderByDescending(x => x.Timestamp)
            .Take(80)
            .ToList();
    }

    private static IReadOnlyList<DeviceFact> BuildDeviceFacts(
        IReadOnlyList<DeviceFact> baseline,
        string deviceId,
        bool isPaired,
        string serviceStatus,
        ConnectionState connection,
        DateTimeOffset now)
    {
        var facts = baseline.ToDictionary(x => $"{x.Category}|{x.Label}", x => x);

        facts["Identity|Device Name"] = new DeviceFact("Identity", "Device Name", Environment.MachineName);
        facts["Identity|Device ID"] = new DeviceFact("Identity", "Device ID", deviceId);
        facts["Runtime|Pairing State"] = new DeviceFact("Runtime", "Pairing State", isPaired ? "Paired" : "Not paired");
        facts["Runtime|Connection"] = new DeviceFact("Runtime", "Connection", connection.ToString());
        facts["Sync/Health|Service Status"] = new DeviceFact("Sync/Health", "Service Status", serviceStatus);
        facts["Sync/Health|Last Heartbeat"] = new DeviceFact("Sync/Health", "Last Heartbeat", now.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"));

        return facts.Values
            .OrderBy(x => x.Category, StringComparer.OrdinalIgnoreCase)
            .ThenBy(x => x.Label, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private void AppendBridgeActivityIfChanged(
        DateTimeOffset now,
        bool serviceInstalled,
        string serviceStatus,
        string deviceId)
    {
        if (_lastServiceInstalled != serviceInstalled || !string.Equals(_lastServiceStatus, serviceStatus, StringComparison.Ordinal))
        {
            _lastServiceInstalled = serviceInstalled;
            _lastServiceStatus = serviceStatus;

            var severity = !serviceInstalled
                ? ActivitySeverity.Error
                : serviceStatus.Contains("running", StringComparison.OrdinalIgnoreCase)
                    ? ActivitySeverity.Info
                    : ActivitySeverity.Warning;

            var detail = serviceInstalled
                ? $"Service {ServiceName} status is {serviceStatus}."
                : $"Service {ServiceName} is not installed.";

            _bridgeActivity.Insert(0, new ActivityEntry(now, severity, "service-bridge", "Service state changed", detail));
        }

        if (!string.Equals(_lastDeviceId, deviceId, StringComparison.Ordinal))
        {
            _lastDeviceId = deviceId;
            if (!string.IsNullOrWhiteSpace(deviceId))
            {
                _bridgeActivity.Insert(0, new ActivityEntry(
                    now,
                    ActivitySeverity.Info,
                    "service-bridge",
                    "Device identity detected",
                    $"Loaded device id from {DeviceIdPath}."));
            }
        }

        if (_bridgeActivity.Count > 24)
        {
            _bridgeActivity.RemoveRange(24, _bridgeActivity.Count - 24);
        }
    }

    private static string ReadDeviceId()
    {
        try
        {
            if (!File.Exists(DeviceIdPath))
            {
                return string.Empty;
            }
            return (File.ReadAllText(DeviceIdPath) ?? string.Empty).Trim();
        }
        catch
        {
            return string.Empty;
        }
    }

    private static (bool installed, ServiceControllerStatus status, string label) QueryServiceStatus()
    {
        try
        {
            using var controller = new ServiceController(ServiceName);
            _ = controller.Status;
            controller.Refresh();
            return (true, controller.Status, controller.Status.ToString());
        }
        catch (InvalidOperationException ex) when (ex.InnerException is Win32Exception win32 && win32.NativeErrorCode == 1060)
        {
            return (false, ServiceControllerStatus.Stopped, "Not Installed");
        }
        catch
        {
            return (false, ServiceControllerStatus.Stopped, "Unavailable");
        }
    }

    private static ConnectionState MapConnection(ServiceControllerStatus status)
    {
        return status switch
        {
            ServiceControllerStatus.Running => ConnectionState.Connected,
            ServiceControllerStatus.StartPending => ConnectionState.Connecting,
            ServiceControllerStatus.ContinuePending => ConnectionState.Reconnecting,
            ServiceControllerStatus.PausePending => ConnectionState.Reconnecting,
            ServiceControllerStatus.StopPending => ConnectionState.Reconnecting,
            ServiceControllerStatus.Paused => ConnectionState.Offline,
            ServiceControllerStatus.Stopped => ConnectionState.Offline,
            _ => ConnectionState.Connecting
        };
    }

    private static void TryStartService()
    {
        try
        {
            using var controller = new ServiceController(ServiceName);
            controller.Refresh();
            if (controller.Status == ServiceControllerStatus.Stopped || controller.Status == ServiceControllerStatus.StopPending)
            {
                controller.Start();
            }
        }
        catch
        {
            // Best-effort only: keep UI responsive even when start attempts fail.
        }
    }

    private bool TryProbeViaPipe(out PipeRuntimeStatus status)
    {
        status = new PipeRuntimeStatus(
            ServiceStatusLabel: "Unavailable",
            Connection: ConnectionState.Offline,
            Endpoint: string.Empty,
            DeviceId: string.Empty,
            ReconnectAttempts: 0,
            AgentPubkey: string.Empty);

        if (!TryPipeRpc("status", out var response))
        {
            return false;
        }

        if (!response.TryGetProperty("ok", out var okNode) || okNode.ValueKind != JsonValueKind.True)
        {
            return false;
        }
        if (!response.TryGetProperty("status", out var statusNode) || statusNode.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        var serviceMode = ReadBool(statusNode, "service_mode", false);
        var communicatorPresent = ReadBool(statusNode, "communicator_present", false);
        var connected = ReadBool(statusNode, "connected", false);
        var connectionRaw = ReadString(statusNode, "connection_state");
        var endpoint = ReadString(statusNode, "endpoint");
        var deviceId = ReadString(statusNode, "device_id");
        var reconnectAttempts = ReadInt(statusNode, "reconnect_attempts", 0);
        var agentPubkey = ReadString(statusNode, "agent_pubkey_b64");

        var statusLabel = serviceMode
            ? $"Service ({connectionRaw})"
            : $"Console ({connectionRaw})";
        if (!communicatorPresent)
        {
            statusLabel = $"{statusLabel} - initializing";
        }

        status = new PipeRuntimeStatus(
            statusLabel,
            connected ? ConnectionState.Connected : ParseConnectionFromWire(connectionRaw),
            endpoint,
            deviceId,
            reconnectAttempts,
            agentPubkey);

        lock (_gate)
        {
            if (!string.IsNullOrWhiteSpace(agentPubkey))
            {
                _lastRuntimeAgentPubkey = agentPubkey;
            }
        }

        return true;
    }

    private bool TrySendPipeCommand(string op, out string reason)
    {
        reason = string.Empty;
        if (!TryPipeRpc(op, out var response))
        {
            reason = "pipe_unavailable";
            return false;
        }

        var ok = response.TryGetProperty("ok", out var okNode) && okNode.ValueKind == JsonValueKind.True;
        if (!ok)
        {
            reason = response.TryGetProperty("reason", out var reasonNode) && reasonNode.ValueKind == JsonValueKind.String
                ? reasonNode.GetString() ?? "rejected"
                : "rejected";
            return false;
        }
        return true;
    }

    private static bool TryPipeRpc(string op, out JsonElement response)
    {
        response = default;
        try
        {
            using var client = new NamedPipeClientStream(
                ".",
                UiBridgePipeName,
                PipeDirection.InOut,
                PipeOptions.None);
            client.Connect(PipeTimeoutMs);

            var payload = JsonSerializer.Serialize(new Dictionary<string, string> { ["op"] = op });
            var bytes = Encoding.UTF8.GetBytes(payload);
            client.Write(bytes, 0, bytes.Length);
            client.Flush();
            try
            {
                client.WaitForPipeDrain();
            }
            catch
            {
                // Best-effort only; some server timing paths may close before drain completes.
            }

            using var ms = new MemoryStream();
            var buffer = new byte[4096];
            int read;
            while ((read = client.Read(buffer, 0, buffer.Length)) > 0)
            {
                ms.Write(buffer, 0, read);
            }

            var raw = Encoding.UTF8.GetString(ms.ToArray());
            if (string.IsNullOrWhiteSpace(raw))
            {
                return false;
            }

            using var doc = JsonDocument.Parse(raw);
            response = doc.RootElement.Clone();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void AddBridgeActivity(DateTimeOffset now, ActivitySeverity severity, string title, string details)
    {
        lock (_gate)
        {
            _bridgeActivity.Insert(0, new ActivityEntry(now, severity, "service-bridge", title, details));
            if (_bridgeActivity.Count > 24)
            {
                _bridgeActivity.RemoveRange(24, _bridgeActivity.Count - 24);
            }
        }
    }

    private static string ReadString(JsonElement node, string property)
    {
        return node.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? (value.GetString() ?? string.Empty)
            : string.Empty;
    }

    private static bool ReadBool(JsonElement node, string property, bool fallback)
    {
        if (!node.TryGetProperty(property, out var value))
        {
            return fallback;
        }
        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => fallback
        };
    }

    private static int ReadInt(JsonElement node, string property, int fallback)
    {
        if (!node.TryGetProperty(property, out var value))
        {
            return fallback;
        }
        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetInt32(out var parsed) => parsed,
            _ => fallback
        };
    }

    private static ConnectionState ParseConnectionFromWire(string state)
    {
        return state.Trim().ToLowerInvariant() switch
        {
            "connected" => ConnectionState.Connected,
            "connecting" => ConnectionState.Connecting,
            "reconnecting" => ConnectionState.Reconnecting,
            "failed" => ConnectionState.AuthFailed,
            "shutdown" => ConnectionState.Offline,
            "disconnected" => ConnectionState.Offline,
            _ => ConnectionState.Connecting
        };
    }

    private int NextOnboardingOperationId()
    {
        lock (_gate)
        {
            _onboardingOperationId += 1;
            return _onboardingOperationId;
        }
    }

    private bool IsCurrentOnboardingOperation(int operationId)
    {
        lock (_gate)
        {
            return operationId == _onboardingOperationId;
        }
    }

    private void ClearPendingPairingData()
    {
        lock (_gate)
        {
            _pendingPairToken = string.Empty;
            _pendingPairSessionId = string.Empty;
            _pendingPairDeviceId = string.Empty;
        }
    }

    private void RememberPendingPairingData(string pairToken, string pairSessionId, string deviceId)
    {
        lock (_gate)
        {
            _pendingPairToken = pairToken;
            _pendingPairSessionId = pairSessionId;
            _pendingPairDeviceId = deviceId;
        }
    }

    private bool TryReadPendingPairingData(out string pairToken, out string pairSessionId, out string deviceId)
    {
        lock (_gate)
        {
            pairToken = _pendingPairToken;
            pairSessionId = _pendingPairSessionId;
            deviceId = _pendingPairDeviceId;
        }

        return !string.IsNullOrWhiteSpace(pairToken);
    }

    private void UpdateBaseline(Func<AgentStateSnapshot, AgentStateSnapshot> updater)
    {
        AgentStateSnapshot merged;
        lock (_gate)
        {
            _baseSnapshot = updater(_baseSnapshot);
            var probe = RuntimeProbeSnapshot();
            merged = MergeSnapshot(_baseSnapshot, probe);
            _snapshot = merged;
        }
        SnapshotChanged?.Invoke(this, merged);
    }

    private async Task CompleteEnrollmentProbeAsync(int operationId)
    {
        await Task.Delay(TimeSpan.FromMilliseconds(300)).ConfigureAwait(false);
        if (!IsCurrentOnboardingOperation(operationId))
        {
            return;
        }

        UpdateBaseline(snapshot =>
        {
            var paired = snapshot.IsPaired || !string.IsNullOrWhiteSpace(ReadDeviceId());
            if (paired)
            {
                var now = DateTimeOffset.UtcNow;
                return snapshot with
                {
                    IsPaired = true,
                    Onboarding = snapshot.Onboarding with
                    {
                        Stage = OnboardingStage.Confirm,
                        DetectState = OnboardingDetectState.Enrolled,
                        ConfirmState = OnboardingConfirmState.EnrollmentComplete,
                        EnrolledAtUtc = snapshot.Onboarding.EnrolledAtUtc ?? now,
                        PairError = string.Empty
                    },
                    CurrentActivity = "Device already enrolled"
                };
            }

            return snapshot with
            {
                Onboarding = snapshot.Onboarding with
                {
                    Stage = OnboardingStage.Detect,
                    DetectState = OnboardingDetectState.NotEnrolled,
                    PairError = string.Empty
                },
                CurrentActivity = "No active enrollment found"
            };
        });
    }

    private async Task RequestPairingTokenAsync(int operationId)
    {
        try
        {
            var pubkey = ResolveAgentPublicKey();
            if (string.IsNullOrWhiteSpace(pubkey))
            {
                UpdateBaseline(snapshot => snapshot with
                {
                    Onboarding = snapshot.Onboarding with
                    {
                        PairState = OnboardingPairState.TokenFailed,
                        PairError = "Agent signing public key not available. Start the agent runtime once, then retry."
                    },
                    CurrentActivity = "Pairing failed: missing agent key"
                });
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Error, "Pairing blocked", "No agent public key available for /api/pair/request.");
                return;
            }

            var hwid = ResolveHwid();
            var payload = new Dictionary<string, object?>
            {
                ["device_name"] = Environment.MachineName,
                ["hwid"] = hwid,
                ["pubkey"] = pubkey
            };

            using var pairResp = await _pairingHttp.PostAsJsonAsync($"{_controlPlaneBaseUrl}/api/pair/request", payload).ConfigureAwait(false);
            var pairRaw = await pairResp.Content.ReadAsStringAsync().ConfigureAwait(false);
            if (!pairResp.IsSuccessStatusCode)
            {
                var reason = ExtractApiError(pairRaw, pairResp.StatusCode);
                UpdateBaseline(snapshot => snapshot with
                {
                    Onboarding = snapshot.Onboarding with
                    {
                        PairState = OnboardingPairState.TokenFailed,
                        PairError = reason
                    },
                    CurrentActivity = "Pairing token request failed"
                });
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Error, "Pair token request failed", reason);
                return;
            }

            using var pairDoc = JsonDocument.Parse(pairRaw);
            var pairRoot = pairDoc.RootElement;
            var pairToken = ReadString(pairRoot, "pair_token");
            var deviceId = ReadString(pairRoot, "device_id");
            if (string.IsNullOrWhiteSpace(pairToken))
            {
                const string reason = "Control plane response did not include pair_token.";
                UpdateBaseline(snapshot => snapshot with
                {
                    Onboarding = snapshot.Onboarding with
                    {
                        PairState = OnboardingPairState.TokenFailed,
                        PairError = reason
                    },
                    CurrentActivity = "Pairing token missing"
                });
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Error, "Pair token missing", reason);
                return;
            }

            var pairSessionId = await TryCreatePairSessionAsync().ConfigureAwait(false);
            var pairingString = BuildPairingPayload(pairToken, pairSessionId, deviceId);

            if (!IsCurrentOnboardingOperation(operationId))
            {
                return;
            }

            RememberPendingPairingData(pairToken, pairSessionId, deviceId);

            UpdateBaseline(snapshot =>
            {
                var nextDeviceId = string.IsNullOrWhiteSpace(deviceId) ? snapshot.DeviceId : deviceId;
                return snapshot with
                {
                    DeviceId = nextDeviceId,
                    Onboarding = snapshot.Onboarding with
                    {
                        Stage = OnboardingStage.Pair,
                        PairState = snapshot.Onboarding.PairMode == OnboardingPairMode.Qr
                            ? OnboardingPairState.QrWaiting
                            : OnboardingPairState.TokenEntry,
                        PairingString = pairingString,
                        PairError = string.Empty
                    },
                    CurrentActivity = "Scan QR with phone app and confirm pairing",
                    Configuration = snapshot.Configuration with
                    {
                        DeviceIdentity = snapshot.Configuration.DeviceIdentity with
                        {
                            DeviceId = nextDeviceId,
                            EnrolledState = "Not Enrolled",
                            EnrolledAtUtc = null
                        }
                    }
                };
            });

            TryWriteRuntimeValue(AgentPubkeyPath, pubkey);
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Info, "Pair token issued", "Phone app can now scan the enrollment QR.");

            var shouldWaitForQr = false;
            lock (_gate)
            {
                shouldWaitForQr = _baseSnapshot.Onboarding.PairMode == OnboardingPairMode.Qr;
            }

            if (shouldWaitForQr)
            {
                _ = WaitForPairConfirmationAsync(operationId, preferQrState: true);
            }
        }
        catch (Exception ex)
        {
            if (!IsCurrentOnboardingOperation(operationId))
            {
                return;
            }

            UpdateBaseline(snapshot => snapshot with
            {
                Onboarding = snapshot.Onboarding with
                {
                    PairState = OnboardingPairState.TokenFailed,
                    PairError = $"Pairing request failed: {ex.Message}"
                },
                CurrentActivity = "Pairing request failed"
            });
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Error, "Pairing request error", ex.Message);
        }
    }

    private async Task<string> TryCreatePairSessionAsync()
    {
        var userJwt = ResolvePairInitJwt();
        if (string.IsNullOrWhiteSpace(userJwt))
        {
            return string.Empty;
        }

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, $"{_controlPlaneBaseUrl}/api/pair/init")
            {
                Content = JsonContent.Create(new Dictionary<string, object?>
                {
                    ["device_label"] = Environment.MachineName
                })
            };
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", userJwt);

            using var response = await _pairingHttp.SendAsync(request).ConfigureAwait(false);
            var raw = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Pair session init skipped", ExtractApiError(raw, response.StatusCode));
                return string.Empty;
            }

            using var doc = JsonDocument.Parse(raw);
            return ReadString(doc.RootElement, "pair_session_id");
        }
        catch (Exception ex)
        {
            AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Pair session init error", ex.Message);
            return string.Empty;
        }
    }

    private async Task WaitForPairConfirmationAsync(int operationId, bool preferQrState)
    {
        if (!TryReadPendingPairingData(out var pairToken, out _, out _))
        {
            return;
        }

        for (var attempt = 0; attempt < PairingPollMaxAttempts; attempt++)
        {
            if (!IsCurrentOnboardingOperation(operationId))
            {
                return;
            }

            AgentTokenPollResult pollResult;
            try
            {
                pollResult = await PollAgentTokenAsync(pairToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                pollResult = new AgentTokenPollResult(false, true, false, string.Empty, string.Empty, ex.Message);
            }

            if (pollResult.Success)
            {
                if (!IsCurrentOnboardingOperation(operationId))
                {
                    return;
                }

                ApplyEnrollmentSuccess(pollResult.DeviceId, pollResult.AgentJwt);
                return;
            }

            if (pollResult.TerminalFailure)
            {
                if (!IsCurrentOnboardingOperation(operationId))
                {
                    return;
                }

                UpdateBaseline(snapshot => snapshot with
                {
                    Onboarding = snapshot.Onboarding with
                    {
                        PairMode = preferQrState ? OnboardingPairMode.Qr : OnboardingPairMode.Token,
                        PairState = preferQrState ? OnboardingPairState.QrWaiting : OnboardingPairState.TokenFailed,
                        PairError = pollResult.Error
                    },
                    CurrentActivity = "Pairing confirmation failed"
                });
                AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Error, "Pairing confirmation failed", pollResult.Error);
                return;
            }

            await Task.Delay(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
        }

        if (!IsCurrentOnboardingOperation(operationId))
        {
            return;
        }

        var timeoutMessage = "Waiting for phone confirmation timed out. Retry QR pairing.";
        UpdateBaseline(snapshot => snapshot with
        {
            Onboarding = snapshot.Onboarding with
            {
                PairMode = preferQrState ? OnboardingPairMode.Qr : OnboardingPairMode.Token,
                PairState = preferQrState ? OnboardingPairState.QrWaiting : OnboardingPairState.TokenFailed,
                PairError = timeoutMessage
            },
            CurrentActivity = "Pairing confirmation timed out"
        });
        AddBridgeActivity(DateTimeOffset.UtcNow, ActivitySeverity.Warning, "Pairing timeout", timeoutMessage);
    }

    private async Task<AgentTokenPollResult> PollAgentTokenAsync(string pairToken)
    {
        var payload = new Dictionary<string, object?>
        {
            ["pair_token"] = pairToken
        };

        using var response = await _pairingHttp.PostAsJsonAsync($"{_controlPlaneBaseUrl}/api/agent/token", payload).ConfigureAwait(false);
        var raw = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            var reason = ExtractApiError(raw, response.StatusCode);
            if (response.StatusCode == HttpStatusCode.Conflict || response.StatusCode == HttpStatusCode.Unauthorized)
            {
                var pending = reason.Contains("device_not_paired", StringComparison.OrdinalIgnoreCase);
                var invalid = reason.Contains("invalid_pair_token", StringComparison.OrdinalIgnoreCase);
                return new AgentTokenPollResult(
                    Success: false,
                    Pending: pending,
                    TerminalFailure: invalid,
                    DeviceId: string.Empty,
                    AgentJwt: string.Empty,
                    Error: reason);
            }

            return new AgentTokenPollResult(
                Success: false,
                Pending: true,
                TerminalFailure: false,
                DeviceId: string.Empty,
                AgentJwt: string.Empty,
                Error: reason);
        }

        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement;
        var jwt = ReadString(root, "jwt");
        if (string.IsNullOrWhiteSpace(jwt))
        {
            jwt = ReadString(root, "agent_jwt");
        }
        var deviceId = ReadString(root, "device_id");
        if (!string.IsNullOrWhiteSpace(jwt))
        {
            return new AgentTokenPollResult(
                Success: true,
                Pending: false,
                TerminalFailure: false,
                DeviceId: deviceId,
                AgentJwt: jwt,
                Error: string.Empty);
        }

        return new AgentTokenPollResult(
            Success: false,
            Pending: true,
            TerminalFailure: false,
            DeviceId: string.Empty,
            AgentJwt: string.Empty,
            Error: "pair_pending");
    }

    private void ApplyEnrollmentSuccess(string deviceIdFromApi, string agentJwt)
    {
        var now = DateTimeOffset.UtcNow;
        string effectiveDeviceId;
        string effectiveEndpoint;
        lock (_gate)
        {
            effectiveDeviceId = string.IsNullOrWhiteSpace(deviceIdFromApi) ? _pendingPairDeviceId : deviceIdFromApi;
            if (string.IsNullOrWhiteSpace(effectiveDeviceId))
            {
                effectiveDeviceId = _baseSnapshot.DeviceId;
            }

            effectiveEndpoint = _baseSnapshot.Configuration.Transport.Endpoint;
        }

        if (!string.IsNullOrWhiteSpace(effectiveDeviceId))
        {
            _ = TryWriteRuntimeValue(DeviceIdPath, effectiveDeviceId);
            Environment.SetEnvironmentVariable("AGENT_DEVICE_ID", effectiveDeviceId, EnvironmentVariableTarget.Process);
        }
        _ = TryWriteRuntimeValue(AgentJwtPath, agentJwt);
        Environment.SetEnvironmentVariable("AGENT_JWT", agentJwt, EnvironmentVariableTarget.Process);

        if (!string.IsNullOrWhiteSpace(effectiveEndpoint))
        {
            _ = TryWriteRuntimeValue(AgentEndpointPath, effectiveEndpoint);
            Environment.SetEnvironmentVariable("AGENT_ENDPOINT", effectiveEndpoint, EnvironmentVariableTarget.Process);
        }

        UpdateBaseline(snapshot =>
        {
            var resolvedDeviceId = string.IsNullOrWhiteSpace(effectiveDeviceId) ? snapshot.DeviceId : effectiveDeviceId;
            return snapshot with
            {
                IsPaired = true,
                DeviceId = resolvedDeviceId,
                Onboarding = snapshot.Onboarding with
                {
                    Stage = OnboardingStage.Confirm,
                    ConfirmState = OnboardingConfirmState.EnrollmentComplete,
                    PairState = OnboardingPairState.TokenEntry,
                    PairError = string.Empty,
                    EnrolledAtUtc = now
                },
                CurrentActivity = "Pairing confirmed. Reconnecting agent runtime",
                Configuration = snapshot.Configuration with
                {
                    DeviceIdentity = snapshot.Configuration.DeviceIdentity with
                    {
                        DeviceId = resolvedDeviceId,
                        EnrolledState = "Enrolled",
                        EnrolledAtUtc = now
                    }
                }
            };
        });

        AddBridgeActivity(now, ActivitySeverity.Info, "Pairing complete", "Persisted agent credentials and requested runtime reconnect.");
        TryStartService();
        _ = TrySendPipeCommand("reconnect", out _);
        PollRuntime();
    }

    private static string BuildPairingPayload(string pairToken, string pairSessionId, string deviceId)
    {
        if (string.IsNullOrWhiteSpace(pairSessionId))
        {
            return pairToken;
        }

        var payload = new Dictionary<string, object?>
        {
            ["type"] = "quoodle_pair",
            ["version"] = 1,
            ["device_id"] = deviceId,
            ["pair_token"] = pairToken,
            ["pair_session_id"] = pairSessionId,
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O"),
            ["controller_url"] = ResolveControlPlaneBaseUrl(),
            ["device_label"] = Environment.MachineName
        };

        return JsonSerializer.Serialize(payload);
    }

    private static string ResolveControlPlaneBaseUrl()
    {
        var url = ReadFirstNonEmptyEnv(
            "QUOODLE_CONTROL_PLANE_URL",
            "QUOODLE_API_BASE",
            "QUOODLE_CONTROL_PLANE",
            "CONTROL_PLANE_URL");

        if (string.IsNullOrWhiteSpace(url))
        {
            var dotEnv = ReadDotEnvValues();
            url = ReadFirstNonEmptyValue(
                dotEnv,
                "CONTROL_PLANE_APP_URL",
                "NEXT_PUBLIC_CONTROL_PLANE_BASE_URL",
                "NEXT_PUBLIC_CONTROL_PLANE_API_URL",
                "CONTROL_PLANE_API_URL");

            if (string.IsNullOrWhiteSpace(url))
            {
                var localPort = ReadFirstNonEmptyValue(dotEnv, "QUOODLE_CONTROL_PLANE_PORT");
                if (!string.IsNullOrWhiteSpace(localPort))
                {
                    url = $"http://localhost:{localPort.Trim()}";
                }
            }
        }

        if (string.IsNullOrWhiteSpace(url))
        {
            url = "http://localhost:8088";
        }

        return NormalizeControlPlaneBaseUrl(url);
    }

    private static string ResolvePairInitJwt()
    {
        var jwt = ReadFirstNonEmptyEnv(
            "QUOODLE_USER_JWT",
            "USER_JWT",
            "QUOODLE_AUTH_JWT");

        if (!string.IsNullOrWhiteSpace(jwt))
        {
            return jwt;
        }

        return ReadFirstNonEmptyValue(
            ReadDotEnvValues(),
            "QUOODLE_USER_JWT",
            "USER_JWT",
            "QUOODLE_AUTH_JWT");
    }

    private string ResolveAgentPublicKey()
    {
        lock (_gate)
        {
            if (!string.IsNullOrWhiteSpace(_lastRuntimeAgentPubkey))
            {
                return _lastRuntimeAgentPubkey;
            }
        }

        if (TryProbeViaPipe(out var status) && !string.IsNullOrWhiteSpace(status.AgentPubkey))
        {
            return status.AgentPubkey;
        }

        var pubkey = ReadFirstNonEmptyEnv(
            "AGENT_EXPECTED_PUBKEY_B64",
            "AGENT_PUBKEY_B64",
            "QUOODLE_AGENT_PUBKEY_B64");
        if (!string.IsNullOrWhiteSpace(pubkey))
        {
            lock (_gate)
            {
                _lastRuntimeAgentPubkey = pubkey;
            }
            return pubkey;
        }

        var filePubkey = ReadRuntimeValue(AgentPubkeyPath);
        if (!string.IsNullOrWhiteSpace(filePubkey))
        {
            lock (_gate)
            {
                _lastRuntimeAgentPubkey = filePubkey;
            }
            return filePubkey;
        }

        return string.Empty;
    }

    private static string ResolveHwid()
    {
        var envHwid = ReadFirstNonEmptyEnv("AGENT_HWID_HASH", "AGENT_HWID", "QUOODLE_HWID");
        if (!string.IsNullOrWhiteSpace(envHwid))
        {
            return envHwid;
        }

        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
            var machineGuid = (key?.GetValue("MachineGuid") as string)?.Trim();
            if (!string.IsNullOrWhiteSpace(machineGuid))
            {
                return machineGuid;
            }
        }
        catch
        {
            // Fallback below.
        }

        return $"windows-{Environment.MachineName}";
    }

    private static string ReadFirstNonEmptyEnv(params string[] keys)
    {
        foreach (var key in keys)
        {
            var value = Environment.GetEnvironmentVariable(key);
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }

        return string.Empty;
    }

    private static string ReadFirstNonEmptyValue(IReadOnlyDictionary<string, string> values, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }

        return string.Empty;
    }

    private static string NormalizeControlPlaneBaseUrl(string raw)
    {
        var value = (raw ?? string.Empty).Trim().TrimEnd('/');
        if (value.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
        {
            value = value[..^4];
        }
        return value;
    }

    private static IReadOnlyDictionary<string, string> ReadDotEnvValues()
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = FindDotEnvPath();
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return result;
        }

        try
        {
            foreach (var line in File.ReadLines(path))
            {
                var trimmed = line.Trim();
                if (string.IsNullOrWhiteSpace(trimmed) || trimmed.StartsWith("#", StringComparison.Ordinal))
                {
                    continue;
                }

                var idx = trimmed.IndexOf('=');
                if (idx <= 0)
                {
                    continue;
                }

                var key = trimmed[..idx].Trim();
                if (string.IsNullOrWhiteSpace(key))
                {
                    continue;
                }

                var value = trimmed[(idx + 1)..].Trim();
                if (value.Length >= 2 &&
                    ((value.StartsWith('"') && value.EndsWith('"')) ||
                     (value.StartsWith('\'') && value.EndsWith('\''))))
                {
                    value = value[1..^1];
                }

                result[key] = value;
            }
        }
        catch
        {
            // Optional local convenience only.
        }

        return result;
    }

    private static string FindDotEnvPath()
    {
        var first = WalkUpForDotEnv(Environment.CurrentDirectory);
        if (!string.IsNullOrWhiteSpace(first))
        {
            return first;
        }

        return WalkUpForDotEnv(AppContext.BaseDirectory);
    }

    private static string WalkUpForDotEnv(string startPath)
    {
        if (string.IsNullOrWhiteSpace(startPath))
        {
            return string.Empty;
        }

        try
        {
            var directory = new DirectoryInfo(Path.GetFullPath(startPath));
            for (var i = 0; i < 10 && directory is not null; i++)
            {
                var candidate = Path.Combine(directory.FullName, ".env");
                if (File.Exists(candidate))
                {
                    return candidate;
                }

                directory = directory.Parent;
            }
        }
        catch
        {
            // Optional local convenience only.
        }

        return string.Empty;
    }

    private static bool TryWriteRuntimeValue(string path, string value)
    {
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }
            File.WriteAllText(path, value.Trim());
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string ReadRuntimeValue(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return string.Empty;
            }
            return (File.ReadAllText(path) ?? string.Empty).Trim();
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string ExtractApiError(string raw, HttpStatusCode statusCode)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return $"HTTP {(int)statusCode}";
        }

        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var reason = ReadString(root, "reason");
            var message = ReadString(root, "message");
            var status = ReadString(root, "status");

            if (!string.IsNullOrWhiteSpace(reason) && !string.IsNullOrWhiteSpace(message))
            {
                return $"{reason}: {message}";
            }
            if (!string.IsNullOrWhiteSpace(reason))
            {
                return reason;
            }
            if (!string.IsNullOrWhiteSpace(message))
            {
                return message;
            }
            if (!string.IsNullOrWhiteSpace(status))
            {
                return status;
            }
        }
        catch
        {
            // Fall through to raw text.
        }

        return raw.Length <= 220 ? raw : raw[..220];
    }

    private void Publish(AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
        SnapshotChanged?.Invoke(this, snapshot);
    }

    private sealed record RuntimeProbe(
        DateTimeOffset ObservedAtUtc,
        bool IsServiceInstalled,
        string ServiceStatusLabel,
        ConnectionState Connection,
        bool IsServiceRunning,
        string DeviceId,
        bool IsPaired,
        int ReconnectAttempts,
        string Endpoint,
        string AgentPubkey);

    private sealed record PipeRuntimeStatus(
        string ServiceStatusLabel,
        ConnectionState Connection,
        string Endpoint,
        string DeviceId,
        int ReconnectAttempts,
        string AgentPubkey);

    private sealed record AgentTokenPollResult(
        bool Success,
        bool Pending,
        bool TerminalFailure,
        string DeviceId,
        string AgentJwt,
        string Error);
}
