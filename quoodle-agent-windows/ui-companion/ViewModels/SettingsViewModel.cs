using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class SettingsViewModel : ObservableObject, IDisposable
{
    private readonly AgentStateStore _store;
    private bool _isApplyingSnapshot;
    private AgentConfiguration _persistedConfiguration;

    private string _deviceId = string.Empty;
    private string _enrolledAccount = string.Empty;
    private string _hwidHash = string.Empty;
    private string _attestationHash = string.Empty;
    private string _agentVersion = string.Empty;
    private string _osBuild = string.Empty;
    private string _localStoragePath = string.Empty;
    private string _enrolledAtText = "-";
    private string _enrolledState = "Not Enrolled";
    private bool _isEnrolled;

    private string _transportEndpoint = string.Empty;
    private string _transportEndpointTag = string.Empty;
    private string _transportHeartbeatInterval = string.Empty;
    private string _transportConnectTimeout = string.Empty;
    private string _transportReconnectMaxAttempts = string.Empty;
    private string _transportReconnectInitialDelay = string.Empty;
    private string _transportReconnectMaxDelay = string.Empty;
    private string _transportReconnectJitter = string.Empty;
    private bool _isTransportDirty;
    private string _transportValidationError = string.Empty;
    private string _transportStatusMessage = string.Empty;
    private bool _transportSavePending;
    private bool _transportTestPending;

    private bool _kernelGuardEnabled;
    private bool _requireCommandSignature;
    private bool _requireKernelSignature;
    private bool _replayProtection;
    private bool _allowUserExit;
    private string _kernelGuardTag = string.Empty;
    private string _requireCommandSignatureTag = string.Empty;
    private string _requireKernelSignatureTag = string.Empty;
    private string _signingAlgorithm = string.Empty;
    private bool _canEditAllowUserExit;
    private string _allowUserExitGateTag = string.Empty;
    private string _allowUserExitGateReason = string.Empty;
    private bool _isSecurityDirty;
    private string _securityStatusMessage = string.Empty;
    private bool _securitySavePending;

    private string _telemetryInterval = string.Empty;
    private string _telemetryHeartbeatInterval = string.Empty;
    private bool _telemetryCpuMetrics;
    private bool _telemetryRamMetrics;
    private bool _telemetryDiskUsage;
    private bool _telemetryNetworkThroughput;
    private bool _telemetryKernelEvents;
    private string _telemetryCpuScopeLabel = string.Empty;
    private string _telemetryRamScopeLabel = string.Empty;
    private string _telemetryDiskScopeLabel = string.Empty;
    private string _telemetryNetworkScopeLabel = string.Empty;
    private string _telemetryKernelScopeLabel = string.Empty;
    private bool _isTelemetryDirty;
    private string _telemetryValidationError = string.Empty;
    private string _telemetryStatusMessage = string.Empty;
    private bool _telemetrySavePending;

    private bool _notifyCommandExecutionFailed;
    private bool _notifyAuthFailed;
    private bool _notifyPolicyHashMismatch;
    private bool _notifyConnectionDegraded;
    private bool _notifyConnectionRecovered;
    private bool _notifyKernelEventReceived;
    private bool _notifyCommandCompletedSuccessfully;
    private string _notificationReconnectWarningThreshold = string.Empty;
    private string _notificationRateLimitWindow = string.Empty;
    private bool _isNotificationsDirty;
    private string _notificationsValidationError = string.Empty;
    private string _notificationsStatusMessage = string.Empty;
    private bool _notificationsSavePending;

    public SettingsViewModel(AgentStateStore store)
    {
        _store = store;
        _persistedConfiguration = AgentConfiguration.CreateDefault(DateTimeOffset.UtcNow, "pending-pairing", Environment.MachineName, "0.0.1", false);

        SaveTransportCommand = new RelayCommand(SaveTransport, () => IsTransportDirty && string.IsNullOrWhiteSpace(TransportValidationError));
        TestTransportCommand = new RelayCommand(TestTransportConnection);
        SaveSecurityCommand = new RelayCommand(SaveSecurity, () => IsSecurityDirty);
        SaveTelemetryCommand = new RelayCommand(SaveTelemetry, () => IsTelemetryDirty && string.IsNullOrWhiteSpace(TelemetryValidationError));
        SaveNotificationsCommand = new RelayCommand(SaveNotifications, () => IsNotificationsDirty && string.IsNullOrWhiteSpace(NotificationsValidationError));

        _store.SnapshotChanged += HandleSnapshotChanged;
        ApplySnapshot(_store.Snapshot);
    }

    public RelayCommand SaveTransportCommand { get; }

    public RelayCommand TestTransportCommand { get; }

    public RelayCommand SaveSecurityCommand { get; }

    public RelayCommand SaveTelemetryCommand { get; }

    public RelayCommand SaveNotificationsCommand { get; }

    public string DeviceId
    {
        get => _deviceId;
        private set => SetProperty(ref _deviceId, value);
    }

    public string EnrolledAccount
    {
        get => _enrolledAccount;
        private set => SetProperty(ref _enrolledAccount, value);
    }

    public string HwidHash
    {
        get => _hwidHash;
        private set => SetProperty(ref _hwidHash, value);
    }

    public string AttestationHash
    {
        get => _attestationHash;
        private set => SetProperty(ref _attestationHash, value);
    }

    public string AgentVersion
    {
        get => _agentVersion;
        private set => SetProperty(ref _agentVersion, value);
    }

    public string OsBuild
    {
        get => _osBuild;
        private set => SetProperty(ref _osBuild, value);
    }

    public string LocalStoragePath
    {
        get => _localStoragePath;
        private set => SetProperty(ref _localStoragePath, value);
    }

    public string EnrolledAtText
    {
        get => _enrolledAtText;
        private set => SetProperty(ref _enrolledAtText, value);
    }

    public string EnrolledState
    {
        get => _enrolledState;
        private set => SetProperty(ref _enrolledState, value);
    }

    public bool IsEnrolled
    {
        get => _isEnrolled;
        private set => SetProperty(ref _isEnrolled, value);
    }

    public string TransportEndpoint
    {
        get => _transportEndpoint;
        set
        {
            if (SetProperty(ref _transportEndpoint, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public string TransportEndpointTag
    {
        get => _transportEndpointTag;
        private set => SetProperty(ref _transportEndpointTag, value);
    }

    public string TransportHeartbeatInterval
    {
        get => _transportHeartbeatInterval;
        set
        {
            if (SetProperty(ref _transportHeartbeatInterval, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public string TransportConnectTimeout
    {
        get => _transportConnectTimeout;
        set
        {
            if (SetProperty(ref _transportConnectTimeout, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public string TransportReconnectMaxAttempts
    {
        get => _transportReconnectMaxAttempts;
        set
        {
            if (SetProperty(ref _transportReconnectMaxAttempts, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public string TransportReconnectInitialDelay
    {
        get => _transportReconnectInitialDelay;
        set
        {
            if (SetProperty(ref _transportReconnectInitialDelay, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public string TransportReconnectMaxDelay
    {
        get => _transportReconnectMaxDelay;
        set
        {
            if (SetProperty(ref _transportReconnectMaxDelay, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public string TransportReconnectJitter
    {
        get => _transportReconnectJitter;
        set
        {
            if (SetProperty(ref _transportReconnectJitter, value))
            {
                HandleTransportDraftChanged();
            }
        }
    }

    public bool IsTransportDirty
    {
        get => _isTransportDirty;
        private set
        {
            if (SetProperty(ref _isTransportDirty, value))
            {
                SaveTransportCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string TransportValidationError
    {
        get => _transportValidationError;
        private set
        {
            if (SetProperty(ref _transportValidationError, value))
            {
                SaveTransportCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string TransportStatusMessage
    {
        get => _transportStatusMessage;
        private set => SetProperty(ref _transportStatusMessage, value);
    }

    public bool KernelGuardEnabled
    {
        get => _kernelGuardEnabled;
        set
        {
            if (SetProperty(ref _kernelGuardEnabled, value))
            {
                HandleSecurityDraftChanged();
            }
        }
    }

    public bool RequireCommandSignature
    {
        get => _requireCommandSignature;
        set
        {
            if (SetProperty(ref _requireCommandSignature, value))
            {
                HandleSecurityDraftChanged();
            }
        }
    }

    public bool RequireKernelSignature
    {
        get => _requireKernelSignature;
        set
        {
            if (SetProperty(ref _requireKernelSignature, value))
            {
                HandleSecurityDraftChanged();
            }
        }
    }

    public bool ReplayProtection
    {
        get => _replayProtection;
        set
        {
            if (SetProperty(ref _replayProtection, value))
            {
                HandleSecurityDraftChanged();
            }
        }
    }

    public bool AllowUserExit
    {
        get => _allowUserExit;
        set
        {
            if (!CanEditAllowUserExit)
            {
                return;
            }

            if (SetProperty(ref _allowUserExit, value))
            {
                HandleSecurityDraftChanged();
            }
        }
    }

    public string KernelGuardTag
    {
        get => _kernelGuardTag;
        private set => SetProperty(ref _kernelGuardTag, value);
    }

    public string RequireCommandSignatureTag
    {
        get => _requireCommandSignatureTag;
        private set => SetProperty(ref _requireCommandSignatureTag, value);
    }

    public string RequireKernelSignatureTag
    {
        get => _requireKernelSignatureTag;
        private set => SetProperty(ref _requireKernelSignatureTag, value);
    }

    public string SigningAlgorithm
    {
        get => _signingAlgorithm;
        private set => SetProperty(ref _signingAlgorithm, value);
    }

    public bool CanEditAllowUserExit
    {
        get => _canEditAllowUserExit;
        private set => SetProperty(ref _canEditAllowUserExit, value);
    }

    public string AllowUserExitGateTag
    {
        get => _allowUserExitGateTag;
        private set => SetProperty(ref _allowUserExitGateTag, value);
    }

    public string AllowUserExitGateReason
    {
        get => _allowUserExitGateReason;
        private set => SetProperty(ref _allowUserExitGateReason, value);
    }

    public bool IsSecurityDirty
    {
        get => _isSecurityDirty;
        private set
        {
            if (SetProperty(ref _isSecurityDirty, value))
            {
                SaveSecurityCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string SecurityStatusMessage
    {
        get => _securityStatusMessage;
        private set => SetProperty(ref _securityStatusMessage, value);
    }

    public string TelemetryInterval
    {
        get => _telemetryInterval;
        set
        {
            if (SetProperty(ref _telemetryInterval, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public string TelemetryHeartbeatInterval
    {
        get => _telemetryHeartbeatInterval;
        set
        {
            if (SetProperty(ref _telemetryHeartbeatInterval, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public bool TelemetryCpuMetrics
    {
        get => _telemetryCpuMetrics;
        set
        {
            if (SetProperty(ref _telemetryCpuMetrics, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public bool TelemetryRamMetrics
    {
        get => _telemetryRamMetrics;
        set
        {
            if (SetProperty(ref _telemetryRamMetrics, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public bool TelemetryDiskUsage
    {
        get => _telemetryDiskUsage;
        set
        {
            if (SetProperty(ref _telemetryDiskUsage, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public bool TelemetryNetworkThroughput
    {
        get => _telemetryNetworkThroughput;
        set
        {
            if (SetProperty(ref _telemetryNetworkThroughput, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public bool TelemetryKernelEvents
    {
        get => _telemetryKernelEvents;
        set
        {
            if (SetProperty(ref _telemetryKernelEvents, value))
            {
                HandleTelemetryDraftChanged();
            }
        }
    }

    public string TelemetryCpuScopeLabel
    {
        get => _telemetryCpuScopeLabel;
        private set => SetProperty(ref _telemetryCpuScopeLabel, value);
    }

    public string TelemetryRamScopeLabel
    {
        get => _telemetryRamScopeLabel;
        private set => SetProperty(ref _telemetryRamScopeLabel, value);
    }

    public string TelemetryDiskScopeLabel
    {
        get => _telemetryDiskScopeLabel;
        private set => SetProperty(ref _telemetryDiskScopeLabel, value);
    }

    public string TelemetryNetworkScopeLabel
    {
        get => _telemetryNetworkScopeLabel;
        private set => SetProperty(ref _telemetryNetworkScopeLabel, value);
    }

    public string TelemetryKernelScopeLabel
    {
        get => _telemetryKernelScopeLabel;
        private set => SetProperty(ref _telemetryKernelScopeLabel, value);
    }

    public bool IsTelemetryDirty
    {
        get => _isTelemetryDirty;
        private set
        {
            if (SetProperty(ref _isTelemetryDirty, value))
            {
                SaveTelemetryCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string TelemetryValidationError
    {
        get => _telemetryValidationError;
        private set
        {
            if (SetProperty(ref _telemetryValidationError, value))
            {
                SaveTelemetryCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string TelemetryStatusMessage
    {
        get => _telemetryStatusMessage;
        private set => SetProperty(ref _telemetryStatusMessage, value);
    }

    public bool NotifyCommandExecutionFailed
    {
        get => _notifyCommandExecutionFailed;
        set
        {
            if (SetProperty(ref _notifyCommandExecutionFailed, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool NotifyAuthFailed
    {
        get => _notifyAuthFailed;
        set
        {
            if (SetProperty(ref _notifyAuthFailed, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool NotifyPolicyHashMismatch
    {
        get => _notifyPolicyHashMismatch;
        set
        {
            if (SetProperty(ref _notifyPolicyHashMismatch, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool NotifyConnectionDegraded
    {
        get => _notifyConnectionDegraded;
        set
        {
            if (SetProperty(ref _notifyConnectionDegraded, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool NotifyConnectionRecovered
    {
        get => _notifyConnectionRecovered;
        set
        {
            if (SetProperty(ref _notifyConnectionRecovered, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool NotifyKernelEventReceived
    {
        get => _notifyKernelEventReceived;
        set
        {
            if (SetProperty(ref _notifyKernelEventReceived, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool NotifyCommandCompletedSuccessfully
    {
        get => _notifyCommandCompletedSuccessfully;
        set
        {
            if (SetProperty(ref _notifyCommandCompletedSuccessfully, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public string NotificationReconnectWarningThreshold
    {
        get => _notificationReconnectWarningThreshold;
        set
        {
            if (SetProperty(ref _notificationReconnectWarningThreshold, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public string NotificationRateLimitWindow
    {
        get => _notificationRateLimitWindow;
        set
        {
            if (SetProperty(ref _notificationRateLimitWindow, value))
            {
                HandleNotificationsDraftChanged();
            }
        }
    }

    public bool IsNotificationsDirty
    {
        get => _isNotificationsDirty;
        private set
        {
            if (SetProperty(ref _isNotificationsDirty, value))
            {
                SaveNotificationsCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string NotificationsValidationError
    {
        get => _notificationsValidationError;
        private set
        {
            if (SetProperty(ref _notificationsValidationError, value))
            {
                SaveNotificationsCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string NotificationsStatusMessage
    {
        get => _notificationsStatusMessage;
        private set => SetProperty(ref _notificationsStatusMessage, value);
    }

    public string GetIdentityValueByKey(string key)
    {
        return key switch
        {
            "device_id" => DeviceId,
            "enrolled_account" => EnrolledAccount,
            "hwid_hash" => HwidHash,
            "attestation_hash" => AttestationHash,
            "agent_version" => AgentVersion,
            "os_build" => OsBuild,
            "local_storage_path" => LocalStoragePath,
            "enrolled_at" => EnrolledAtText,
            _ => string.Empty
        };
    }

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        ApplySnapshot(snapshot);
    }

    private void ApplySnapshot(AgentStateSnapshot snapshot)
    {
        _isApplyingSnapshot = true;
        try
        {
            _persistedConfiguration = snapshot.Configuration;

            ApplyIdentity(snapshot.Configuration.DeviceIdentity);
            ApplyTransport(snapshot.Configuration.Transport);
            ApplySecurity(snapshot.Configuration.Security);
            ApplyTelemetry(snapshot.Configuration.TelemetryPolicy);
            ApplyNotifications(snapshot.Configuration.Notifications);

            TransportStatusMessage = ResolveTransportStatusMessage();
            SecurityStatusMessage = ResolveSectionStatusMessage(ref _securitySavePending, "Security policy saved.");
            TelemetryStatusMessage = ResolveSectionStatusMessage(ref _telemetrySavePending, "Telemetry policy saved.");
            NotificationsStatusMessage = ResolveSectionStatusMessage(ref _notificationsSavePending, "Notification policy saved.");
        }
        finally
        {
            _isApplyingSnapshot = false;
        }

        RecalculateTransportState();
        RecalculateSecurityState();
        RecalculateTelemetryState();
        RecalculateNotificationsState();
    }

    private void ApplyIdentity(DeviceIdentityConfig identity)
    {
        DeviceId = NormalizeIdentityValue(identity.DeviceId);
        EnrolledAccount = NormalizeIdentityValue(identity.EnrolledAccount);
        HwidHash = NormalizeIdentityValue(identity.HwidHash);
        AttestationHash = NormalizeIdentityValue(identity.AttestationHash);
        AgentVersion = NormalizeIdentityValue(identity.AgentVersion);
        OsBuild = NormalizeIdentityValue(identity.OsBuild);
        LocalStoragePath = NormalizeIdentityValue(identity.LocalStoragePath);
        EnrolledAtText = identity.EnrolledAtUtc?.LocalDateTime.ToString("M/d/yyyy, h:mm:ss tt") ?? "-";
        EnrolledState = string.IsNullOrWhiteSpace(identity.EnrolledState) ? "Not Enrolled" : identity.EnrolledState;
        IsEnrolled = string.Equals(EnrolledState, "Enrolled", StringComparison.OrdinalIgnoreCase);
    }

    private void ApplyTransport(TransportConfig transport)
    {
        TransportEndpoint = transport.Endpoint;
        TransportEndpointTag = transport.EndpointEnvTag;
        TransportHeartbeatInterval = transport.HeartbeatIntervalSeconds.ToString();
        TransportConnectTimeout = transport.ConnectTimeoutMs.ToString();
        TransportReconnectMaxAttempts = transport.ReconnectMaxAttempts.ToString();
        TransportReconnectInitialDelay = transport.ReconnectInitialDelayMs.ToString();
        TransportReconnectMaxDelay = transport.ReconnectMaxDelayMs.ToString();
        TransportReconnectJitter = transport.ReconnectJitterMs.ToString();
    }

    private void ApplySecurity(SecurityConfig security)
    {
        KernelGuardEnabled = security.KernelGuardEnabled;
        RequireCommandSignature = security.RequireCommandSignature;
        RequireKernelSignature = security.RequireKernelSignature;
        ReplayProtection = security.ReplayProtection;
        _allowUserExit = security.AllowUserExit;
        RaisePropertyChanged(nameof(AllowUserExit));
        KernelGuardTag = security.KernelGuardTag;
        RequireCommandSignatureTag = security.RequireCommandSignatureTag;
        RequireKernelSignatureTag = security.RequireKernelSignatureTag;
        SigningAlgorithm = security.SigningAlgorithm;
        CanEditAllowUserExit = security.PolicyGates.CanEditAllowUserExit;
        AllowUserExitGateTag = security.PolicyGates.AllowUserExitTag;
        AllowUserExitGateReason = security.PolicyGates.AllowUserExitReason;
    }

    private void ApplyTelemetry(TelemetryPolicyConfig telemetry)
    {
        TelemetryInterval = telemetry.TelemetryIntervalSeconds.ToString();
        TelemetryHeartbeatInterval = telemetry.HeartbeatIntervalSeconds.ToString();
        TelemetryCpuMetrics = telemetry.CpuMetrics;
        TelemetryRamMetrics = telemetry.RamMetrics;
        TelemetryDiskUsage = telemetry.DiskUsage;
        TelemetryNetworkThroughput = telemetry.NetworkThroughput;
        TelemetryKernelEvents = telemetry.KernelEvents;
        TelemetryCpuScopeLabel = telemetry.CpuScopeLabel;
        TelemetryRamScopeLabel = telemetry.RamScopeLabel;
        TelemetryDiskScopeLabel = telemetry.DiskScopeLabel;
        TelemetryNetworkScopeLabel = telemetry.NetworkScopeLabel;
        TelemetryKernelScopeLabel = telemetry.KernelScopeLabel;
    }

    private void ApplyNotifications(NotificationPolicyConfig notifications)
    {
        NotifyCommandExecutionFailed = notifications.NotifyCommandExecutionFailed;
        NotifyAuthFailed = notifications.NotifyAuthFailed;
        NotifyPolicyHashMismatch = notifications.NotifyPolicyHashMismatch;
        NotifyConnectionDegraded = notifications.NotifyConnectionDegraded;
        NotifyConnectionRecovered = notifications.NotifyConnectionRecovered;
        NotifyKernelEventReceived = notifications.NotifyKernelEventReceived;
        NotifyCommandCompletedSuccessfully = notifications.NotifyCommandCompletedSuccessfully;
        NotificationReconnectWarningThreshold = notifications.ReconnectWarningThresholdSeconds.ToString();
        NotificationRateLimitWindow = notifications.RateLimitWindowMinutes.ToString();
    }

    private void HandleTransportDraftChanged()
    {
        if (_isApplyingSnapshot)
        {
            return;
        }

        RecalculateTransportState();
    }

    private void HandleSecurityDraftChanged()
    {
        if (_isApplyingSnapshot)
        {
            return;
        }

        RecalculateSecurityState();
    }

    private void HandleTelemetryDraftChanged()
    {
        if (_isApplyingSnapshot)
        {
            return;
        }

        RecalculateTelemetryState();
    }

    private void HandleNotificationsDraftChanged()
    {
        if (_isApplyingSnapshot)
        {
            return;
        }

        RecalculateNotificationsState();
    }

    private void RecalculateTransportState()
    {
        var isValid = TryBuildTransportDraft(out var draft, out var error);
        TransportValidationError = error;
        IsTransportDirty = isValid && !draft.Equals(_persistedConfiguration.Transport);
    }

    private void RecalculateSecurityState()
    {
        var draft = BuildSecurityDraft();
        IsSecurityDirty = !draft.Equals(_persistedConfiguration.Security);
    }

    private void RecalculateTelemetryState()
    {
        var isValid = TryBuildTelemetryDraft(out var draft, out var error);
        TelemetryValidationError = error;
        IsTelemetryDirty = isValid && !draft.Equals(_persistedConfiguration.TelemetryPolicy);
    }

    private void RecalculateNotificationsState()
    {
        var isValid = TryBuildNotificationsDraft(out var draft, out var error);
        NotificationsValidationError = error;
        IsNotificationsDirty = isValid && !draft.Equals(_persistedConfiguration.Notifications);
    }

    private bool TryBuildTransportDraft(out TransportConfig draft, out string error)
    {
        draft = _persistedConfiguration.Transport;

        if (string.IsNullOrWhiteSpace(TransportEndpoint))
        {
            error = "WSS endpoint is required.";
            return false;
        }

        if (!TryParsePositiveInt(TransportHeartbeatInterval, "Heartbeat interval", out var heartbeat, out error)
            || !TryParsePositiveInt(TransportConnectTimeout, "Connect timeout", out var timeout, out error)
            || !TryParsePositiveInt(TransportReconnectMaxAttempts, "Reconnect max attempts", out var maxAttempts, out error)
            || !TryParsePositiveInt(TransportReconnectInitialDelay, "Reconnect initial delay", out var initialDelay, out error)
            || !TryParsePositiveInt(TransportReconnectMaxDelay, "Reconnect max delay", out var maxDelay, out error)
            || !TryParsePositiveInt(TransportReconnectJitter, "Reconnect jitter", out var jitter, out error))
        {
            return false;
        }

        draft = _persistedConfiguration.Transport with
        {
            Endpoint = TransportEndpoint.Trim(),
            EndpointEnvTag = string.IsNullOrWhiteSpace(TransportEndpointTag) ? _persistedConfiguration.Transport.EndpointEnvTag : TransportEndpointTag.Trim(),
            HeartbeatIntervalSeconds = heartbeat,
            ConnectTimeoutMs = timeout,
            ReconnectMaxAttempts = maxAttempts,
            ReconnectInitialDelayMs = initialDelay,
            ReconnectMaxDelayMs = maxDelay,
            ReconnectJitterMs = jitter
        };

        error = string.Empty;
        return true;
    }

    private SecurityConfig BuildSecurityDraft()
    {
        var persisted = _persistedConfiguration.Security;
        return persisted with
        {
            KernelGuardEnabled = KernelGuardEnabled,
            RequireCommandSignature = RequireCommandSignature,
            RequireKernelSignature = RequireKernelSignature,
            ReplayProtection = ReplayProtection,
            AllowUserExit = CanEditAllowUserExit ? _allowUserExit : persisted.AllowUserExit
        };
    }

    private bool TryBuildTelemetryDraft(out TelemetryPolicyConfig draft, out string error)
    {
        draft = _persistedConfiguration.TelemetryPolicy;

        if (!TryParsePositiveInt(TelemetryInterval, "Telemetry interval", out var telemetryInterval, out error)
            || !TryParsePositiveInt(TelemetryHeartbeatInterval, "Heartbeat interval", out var heartbeatInterval, out error))
        {
            return false;
        }

        draft = _persistedConfiguration.TelemetryPolicy with
        {
            TelemetryIntervalSeconds = telemetryInterval,
            HeartbeatIntervalSeconds = heartbeatInterval,
            CpuMetrics = TelemetryCpuMetrics,
            RamMetrics = TelemetryRamMetrics,
            DiskUsage = TelemetryDiskUsage,
            NetworkThroughput = TelemetryNetworkThroughput,
            KernelEvents = TelemetryKernelEvents
        };

        error = string.Empty;
        return true;
    }

    private bool TryBuildNotificationsDraft(out NotificationPolicyConfig draft, out string error)
    {
        draft = _persistedConfiguration.Notifications;

        if (!TryParsePositiveInt(NotificationReconnectWarningThreshold, "Reconnect warning threshold", out var warningThreshold, out error)
            || !TryParsePositiveInt(NotificationRateLimitWindow, "Rate limit window", out var rateLimitWindow, out error))
        {
            return false;
        }

        draft = _persistedConfiguration.Notifications with
        {
            NotifyCommandExecutionFailed = NotifyCommandExecutionFailed,
            NotifyAuthFailed = NotifyAuthFailed,
            NotifyPolicyHashMismatch = NotifyPolicyHashMismatch,
            NotifyConnectionDegraded = NotifyConnectionDegraded,
            NotifyConnectionRecovered = NotifyConnectionRecovered,
            NotifyKernelEventReceived = NotifyKernelEventReceived,
            NotifyCommandCompletedSuccessfully = NotifyCommandCompletedSuccessfully,
            ReconnectWarningThresholdSeconds = warningThreshold,
            RateLimitWindowMinutes = rateLimitWindow
        };

        error = string.Empty;
        return true;
    }

    private void SaveTransport()
    {
        if (!TryBuildTransportDraft(out var draft, out _))
        {
            return;
        }

        _transportSavePending = true;
        _transportTestPending = false;
        TransportStatusMessage = "Saving changes...";
        _store.SaveTransportConfig(draft);
    }

    private void TestTransportConnection()
    {
        _transportSavePending = false;
        _transportTestPending = true;
        TransportStatusMessage = "Testing connection...";
        _store.TestTransportConnection();
    }

    private void SaveSecurity()
    {
        var draft = BuildSecurityDraft();
        _securitySavePending = true;
        SecurityStatusMessage = "Saving security policy...";
        _store.SaveSecurityConfig(draft);
    }

    private void SaveTelemetry()
    {
        if (!TryBuildTelemetryDraft(out var draft, out _))
        {
            return;
        }

        _telemetrySavePending = true;
        TelemetryStatusMessage = "Saving telemetry policy...";
        _store.SaveTelemetryPolicy(draft);
    }

    private void SaveNotifications()
    {
        if (!TryBuildNotificationsDraft(out var draft, out _))
        {
            return;
        }

        _notificationsSavePending = true;
        NotificationsStatusMessage = "Saving notification policy...";
        _store.SaveNotificationConfig(draft);
    }

    private string ResolveTransportStatusMessage()
    {
        if (_transportSavePending)
        {
            _transportSavePending = false;
            return "Transport settings saved.";
        }

        if (_transportTestPending)
        {
            _transportTestPending = false;
            return "Connection test succeeded.";
        }

        return string.Empty;
    }

    private static string ResolveSectionStatusMessage(ref bool pending, string message)
    {
        if (!pending)
        {
            return string.Empty;
        }

        pending = false;
        return message;
    }

    private static bool TryParsePositiveInt(string text, string fieldName, out int value, out string error)
    {
        if (!int.TryParse(text?.Trim(), out value) || value <= 0)
        {
            error = $"{fieldName} must be a positive integer.";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static string NormalizeIdentityValue(string value) => string.IsNullOrWhiteSpace(value) ? "-" : value;

    public void Dispose()
    {
        _store.SnapshotChanged -= HandleSnapshotChanged;
    }
}

