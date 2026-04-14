using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.ComponentModel;
using Windows.ApplicationModel.DataTransfer;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class SettingsPage : Page
{
    private readonly SettingsViewModel _vm;
    private bool _isRendering;

    public SettingsPage()
    {
        InitializeComponent();
        _vm = new SettingsViewModel(App.StateStore);
        _vm.PropertyChanged += HandleViewModelPropertyChanged;
        Unloaded += OnPageUnloaded;
        Render();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (DispatcherQueue.HasThreadAccess)
        {
            Render();
            return;
        }

        _ = DispatcherQueue.TryEnqueue(Render);
    }

    private void Render()
    {
        _isRendering = true;
        try
        {
            RenderIdentity();
            RenderTransport();
            RenderSecurity();
            RenderTelemetry();
            RenderNotifications();
        }
        finally
        {
            _isRendering = false;
        }
    }

    private void RenderIdentity()
    {
        IdentityEnrolledBadgeText.Text = _vm.IsEnrolled ? "Enrolled" : "Pending";
        IdentityEnrolledBadge.Background = BrushOf(_vm.IsEnrolled ? "ChipSuccessBackgroundBrush" : "ChipWarningBackgroundBrush");
        IdentityEnrolledBadge.BorderBrush = BrushOf(_vm.IsEnrolled ? "HeaderPanelBorderBrush" : "WarningPanelBorderBrush");
        IdentityEnrolledBadgeText.Foreground = BrushOf(_vm.IsEnrolled ? "ChipSuccessForegroundBrush" : "ChipWarningForegroundBrush");

        DeviceIdValueText.Text = _vm.DeviceId;
        EnrolledAccountValueText.Text = _vm.EnrolledAccount;
        HwidHashValueText.Text = _vm.HwidHash;
        AttestationHashValueText.Text = _vm.AttestationHash;
        AgentVersionValueText.Text = _vm.AgentVersion;
        OsBuildValueText.Text = _vm.OsBuild;
        LocalStoragePathValueText.Text = _vm.LocalStoragePath;
        EnrolledAtValueText.Text = _vm.EnrolledAtText;
    }

    private void RenderTransport()
    {
        TransportEndpointTagText.Text = _vm.TransportEndpointTag;
        SetTextIfDifferent(TransportEndpointBox, _vm.TransportEndpoint);
        SetTextIfDifferent(TransportHeartbeatIntervalBox, _vm.TransportHeartbeatInterval);
        SetTextIfDifferent(TransportConnectTimeoutBox, _vm.TransportConnectTimeout);
        SetTextIfDifferent(TransportReconnectMaxAttemptsBox, _vm.TransportReconnectMaxAttempts);
        SetTextIfDifferent(TransportReconnectInitialDelayBox, _vm.TransportReconnectInitialDelay);
        SetTextIfDifferent(TransportReconnectMaxDelayBox, _vm.TransportReconnectMaxDelay);
        SetTextIfDifferent(TransportReconnectJitterBox, _vm.TransportReconnectJitter);

        SaveTransportButton.IsEnabled = _vm.SaveTransportCommand.CanExecute(null);
        TestConnectionButton.IsEnabled = _vm.TestTransportCommand.CanExecute(null);
        RenderMessage(TransportValidationText, _vm.TransportValidationError, "ChipDangerForegroundBrush");
        RenderMessage(TransportStatusText, _vm.TransportStatusMessage, "TextSecondaryBrush");
    }

    private void RenderSecurity()
    {
        KernelGuardTagText.Text = _vm.KernelGuardTag;
        RequireCommandSignatureTagText.Text = _vm.RequireCommandSignatureTag;
        RequireKernelSignatureTagText.Text = _vm.RequireKernelSignatureTag;
        SigningAlgorithmBadgeText.Text = _vm.SigningAlgorithm;

        KernelGuardSwitch.IsOn = _vm.KernelGuardEnabled;
        RequireCommandSignatureSwitch.IsOn = _vm.RequireCommandSignature;
        RequireKernelSignatureSwitch.IsOn = _vm.RequireKernelSignature;
        ReplayProtectionSwitch.IsOn = _vm.ReplayProtection;
        AllowUserExitSwitch.IsOn = _vm.AllowUserExit;
        AllowUserExitSwitch.IsEnabled = _vm.CanEditAllowUserExit;
        AllowUserExitGateTagBadge.Visibility = _vm.CanEditAllowUserExit ? Visibility.Collapsed : Visibility.Visible;
        AllowUserExitGateTagText.Text = _vm.AllowUserExitGateTag;
        AllowUserExitGateReasonText.Text = _vm.AllowUserExitGateReason;
        AllowUserExitGateReasonText.Visibility = _vm.CanEditAllowUserExit ? Visibility.Collapsed : Visibility.Visible;

        SaveSecurityButton.IsEnabled = _vm.SaveSecurityCommand.CanExecute(null);
        RenderMessage(SecurityStatusText, _vm.SecurityStatusMessage, "TextSecondaryBrush");
    }

    private void RenderTelemetry()
    {
        SetTextIfDifferent(TelemetryIntervalBox, _vm.TelemetryInterval);
        SetTextIfDifferent(TelemetryHeartbeatIntervalBox, _vm.TelemetryHeartbeatInterval);
        TelemetryCpuSwitch.IsOn = _vm.TelemetryCpuMetrics;
        TelemetryRamSwitch.IsOn = _vm.TelemetryRamMetrics;
        TelemetryDiskSwitch.IsOn = _vm.TelemetryDiskUsage;
        TelemetryNetworkSwitch.IsOn = _vm.TelemetryNetworkThroughput;
        TelemetryKernelSwitch.IsOn = _vm.TelemetryKernelEvents;

        TelemetryCpuScopeLabelText.Text = _vm.TelemetryCpuScopeLabel;
        TelemetryRamScopeLabelText.Text = _vm.TelemetryRamScopeLabel;
        TelemetryDiskScopeLabelText.Text = _vm.TelemetryDiskScopeLabel;
        TelemetryNetworkScopeLabelText.Text = _vm.TelemetryNetworkScopeLabel;
        TelemetryKernelScopeLabelText.Text = _vm.TelemetryKernelScopeLabel;

        SaveTelemetryButton.IsEnabled = _vm.SaveTelemetryCommand.CanExecute(null);
        RenderMessage(TelemetryValidationText, _vm.TelemetryValidationError, "ChipDangerForegroundBrush");
        RenderMessage(TelemetryStatusText, _vm.TelemetryStatusMessage, "TextSecondaryBrush");
    }

    private void RenderNotifications()
    {
        NotifyCommandExecutionFailedSwitch.IsOn = _vm.NotifyCommandExecutionFailed;
        NotifyAuthFailedSwitch.IsOn = _vm.NotifyAuthFailed;
        NotifyPolicyHashMismatchSwitch.IsOn = _vm.NotifyPolicyHashMismatch;
        NotifyConnectionDegradedSwitch.IsOn = _vm.NotifyConnectionDegraded;
        NotifyConnectionRecoveredSwitch.IsOn = _vm.NotifyConnectionRecovered;
        NotifyKernelEventReceivedSwitch.IsOn = _vm.NotifyKernelEventReceived;
        NotifyCommandCompletedSuccessfullySwitch.IsOn = _vm.NotifyCommandCompletedSuccessfully;
        SetTextIfDifferent(ReconnectWarningThresholdBox, _vm.NotificationReconnectWarningThreshold);
        SetTextIfDifferent(RateLimitWindowBox, _vm.NotificationRateLimitWindow);

        SaveNotificationsButton.IsEnabled = _vm.SaveNotificationsCommand.CanExecute(null);
        RenderMessage(NotificationsValidationText, _vm.NotificationsValidationError, "ChipDangerForegroundBrush");
        RenderMessage(NotificationsStatusText, _vm.NotificationsStatusMessage, "TextSecondaryBrush");
    }

    private void RenderMessage(TextBlock target, string value, string brushKey)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            target.Text = string.Empty;
            target.Visibility = Visibility.Collapsed;
            return;
        }

        target.Text = value;
        target.Foreground = BrushOf(brushKey);
        target.Visibility = Visibility.Visible;
    }

    private Brush BrushOf(string key)
    {
        if (Resources.TryGetValue(key, out var localObj) && localObj is Brush localBrush)
        {
            return localBrush;
        }

        if (Application.Current.Resources.TryGetValue(key, out var appObj) && appObj is Brush appBrush)
        {
            return appBrush;
        }

        return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    private void SetTextIfDifferent(TextBox box, string value)
    {
        if (!string.Equals(box.Text, value, StringComparison.Ordinal))
        {
            box.Text = value;
        }
    }

    private void OnCopyIdentityValue(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string key)
        {
            return;
        }

        var value = _vm.GetIdentityValueByKey(key);
        if (string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        var package = new DataPackage();
        package.SetText(value);
        Clipboard.SetContent(package);
    }

    private void OnTransportFieldChanged(object sender, TextChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.TransportEndpoint = TransportEndpointBox.Text;
        _vm.TransportHeartbeatInterval = TransportHeartbeatIntervalBox.Text;
        _vm.TransportConnectTimeout = TransportConnectTimeoutBox.Text;
        _vm.TransportReconnectMaxAttempts = TransportReconnectMaxAttemptsBox.Text;
        _vm.TransportReconnectInitialDelay = TransportReconnectInitialDelayBox.Text;
        _vm.TransportReconnectMaxDelay = TransportReconnectMaxDelayBox.Text;
        _vm.TransportReconnectJitter = TransportReconnectJitterBox.Text;
    }

    private void OnSecurityToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.KernelGuardEnabled = KernelGuardSwitch.IsOn;
        _vm.RequireCommandSignature = RequireCommandSignatureSwitch.IsOn;
        _vm.RequireKernelSignature = RequireKernelSignatureSwitch.IsOn;
        _vm.ReplayProtection = ReplayProtectionSwitch.IsOn;
        if (_vm.CanEditAllowUserExit)
        {
            _vm.AllowUserExit = AllowUserExitSwitch.IsOn;
        }
    }

    private void OnTelemetryFieldChanged(object sender, TextChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.TelemetryInterval = TelemetryIntervalBox.Text;
        _vm.TelemetryHeartbeatInterval = TelemetryHeartbeatIntervalBox.Text;
    }

    private void OnTelemetryToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.TelemetryCpuMetrics = TelemetryCpuSwitch.IsOn;
        _vm.TelemetryRamMetrics = TelemetryRamSwitch.IsOn;
        _vm.TelemetryDiskUsage = TelemetryDiskSwitch.IsOn;
        _vm.TelemetryNetworkThroughput = TelemetryNetworkSwitch.IsOn;
        _vm.TelemetryKernelEvents = TelemetryKernelSwitch.IsOn;
    }

    private void OnNotificationToggleChanged(object sender, RoutedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.NotifyCommandExecutionFailed = NotifyCommandExecutionFailedSwitch.IsOn;
        _vm.NotifyAuthFailed = NotifyAuthFailedSwitch.IsOn;
        _vm.NotifyPolicyHashMismatch = NotifyPolicyHashMismatchSwitch.IsOn;
        _vm.NotifyConnectionDegraded = NotifyConnectionDegradedSwitch.IsOn;
        _vm.NotifyConnectionRecovered = NotifyConnectionRecoveredSwitch.IsOn;
        _vm.NotifyKernelEventReceived = NotifyKernelEventReceivedSwitch.IsOn;
        _vm.NotifyCommandCompletedSuccessfully = NotifyCommandCompletedSuccessfullySwitch.IsOn;
    }

    private void OnNotificationFieldChanged(object sender, TextChangedEventArgs e)
    {
        if (_isRendering)
        {
            return;
        }

        _vm.NotificationReconnectWarningThreshold = ReconnectWarningThresholdBox.Text;
        _vm.NotificationRateLimitWindow = RateLimitWindowBox.Text;
    }

    private void OnSaveTransportClick(object sender, RoutedEventArgs e)
    {
        if (_vm.SaveTransportCommand.CanExecute(null))
        {
            _vm.SaveTransportCommand.Execute(null);
        }
    }

    private void OnTestConnectionClick(object sender, RoutedEventArgs e)
    {
        if (_vm.TestTransportCommand.CanExecute(null))
        {
            _vm.TestTransportCommand.Execute(null);
        }
    }

    private void OnSaveSecurityClick(object sender, RoutedEventArgs e)
    {
        if (_vm.SaveSecurityCommand.CanExecute(null))
        {
            _vm.SaveSecurityCommand.Execute(null);
        }
    }

    private void OnSaveTelemetryClick(object sender, RoutedEventArgs e)
    {
        if (_vm.SaveTelemetryCommand.CanExecute(null))
        {
            _vm.SaveTelemetryCommand.Execute(null);
        }
    }

    private void OnSaveNotificationsClick(object sender, RoutedEventArgs e)
    {
        if (_vm.SaveNotificationsCommand.CanExecute(null))
        {
            _vm.SaveNotificationsCommand.Execute(null);
        }
    }

    private void OnPageUnloaded(object sender, RoutedEventArgs e)
    {
        Unloaded -= OnPageUnloaded;
        _vm.PropertyChanged -= HandleViewModelPropertyChanged;
        _vm.Dispose();
    }
}
