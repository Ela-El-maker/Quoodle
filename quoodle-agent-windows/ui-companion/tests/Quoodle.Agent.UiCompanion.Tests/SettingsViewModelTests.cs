using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using Quoodle.Agent.UiCompanion.ViewModels;
using Xunit;

namespace Quoodle.Agent.UiCompanion.Tests;

public sealed class SettingsViewModelTests
{
    [Fact]
    public void TransportDraftTracksDirtyStateAndSavesThroughProvider()
    {
        var provider = new SettingsTestProvider(BuildSnapshot());
        using var store = new AgentStateStore(provider);
        using var vm = new SettingsViewModel(store);

        vm.TransportConnectTimeout = "15000";

        Assert.True(vm.IsTransportDirty);
        Assert.True(vm.SaveTransportCommand.CanExecute(null));

        vm.SaveTransportCommand.Execute(null);

        Assert.Equal(1, provider.TransportSaveCount);
        Assert.Equal(15000, provider.Snapshot.Configuration.Transport.ConnectTimeoutMs);
        Assert.False(vm.IsTransportDirty);
    }

    [Fact]
    public void ValidationBlocksSectionSaveForInvalidNumericInput()
    {
        var provider = new SettingsTestProvider(BuildSnapshot());
        using var store = new AgentStateStore(provider);
        using var vm = new SettingsViewModel(store);

        vm.TelemetryInterval = "abc";

        Assert.Contains("positive integer", vm.TelemetryValidationError, StringComparison.OrdinalIgnoreCase);
        Assert.False(vm.SaveTelemetryCommand.CanExecute(null));
    }

    [Fact]
    public void PolicyGatedSecurityFieldCannotBeEdited()
    {
        var baseSnapshot = BuildSnapshot();
        var snapshot = baseSnapshot with
        {
            Configuration = baseSnapshot.Configuration with
            {
                Security = baseSnapshot.Configuration.Security with
                {
                    AllowUserExit = false,
                    PolicyGates = new SecurityPolicyGates(false, "policy-gated", "Restricted by policy capability allow_user_exit=false")
                }
            }
        };

        var provider = new SettingsTestProvider(snapshot);
        using var store = new AgentStateStore(provider);
        using var vm = new SettingsViewModel(store);

        vm.AllowUserExit = true;

        Assert.False(vm.AllowUserExit);
        Assert.False(vm.IsSecurityDirty);
    }

    [Fact]
    public void NotificationsSaveUpdatesOnlyNotificationsSection()
    {
        var provider = new SettingsTestProvider(BuildSnapshot());
        using var store = new AgentStateStore(provider);
        using var vm = new SettingsViewModel(store);

        var beforeTransportTimeout = provider.Snapshot.Configuration.Transport.ConnectTimeoutMs;
        vm.NotifyKernelEventReceived = true;
        vm.NotificationRateLimitWindow = "12";

        Assert.True(vm.IsNotificationsDirty);
        vm.SaveNotificationsCommand.Execute(null);

        Assert.Equal(1, provider.NotificationsSaveCount);
        Assert.True(provider.Snapshot.Configuration.Notifications.NotifyKernelEventReceived);
        Assert.Equal(12, provider.Snapshot.Configuration.Notifications.RateLimitWindowMinutes);
        Assert.Equal(beforeTransportTimeout, provider.Snapshot.Configuration.Transport.ConnectTimeoutMs);
    }

    [Fact]
    public void MockProviderAppliesSectionSavesAndPolicyGates()
    {
        using var provider = new MockAgentStateProvider();

        var baseSnapshot = provider.Snapshot;
        provider.SaveTransportConfig(baseSnapshot.Configuration.Transport with
        {
            Endpoint = "wss://gateway.quoodle.io/agent-v2",
            ConnectTimeoutMs = 14000
        });

        var afterTransport = provider.Snapshot;
        Assert.Equal("wss://gateway.quoodle.io/agent-v2", afterTransport.Configuration.Transport.Endpoint);
        Assert.Equal(14000, afterTransport.Configuration.Transport.ConnectTimeoutMs);

        provider.SaveSecurityConfig(afterTransport.Configuration.Security with
        {
            AllowUserExit = true
        });

        var afterSecurity = provider.Snapshot;
        Assert.False(afterSecurity.Configuration.Security.AllowUserExit);

        provider.TestTransportConnection();
        var afterTest = provider.Snapshot;
        Assert.Contains(afterTest.Activity, x => x.Title.Contains("Transport test OK", StringComparison.OrdinalIgnoreCase));
    }

    private static AgentStateSnapshot BuildSnapshot()
    {
        var now = DateTimeOffset.UtcNow;
        var config = AgentConfiguration.CreateDefault(now, "PC001", "WORKSTATION-PC001", "0.0.1", true);

        return AgentStateSnapshot.CreateInitial() with
        {
            IsPaired = true,
            DeviceId = "PC001",
            DeviceName = "WORKSTATION-PC001",
            AgentVersion = "0.0.1",
            Configuration = config
        };
    }
}

internal sealed class SettingsTestProvider : IAgentStateProvider
{
    public SettingsTestProvider(AgentStateSnapshot snapshot)
    {
        Snapshot = snapshot;
    }

    public AgentStateSnapshot Snapshot { get; private set; }

    public int TransportSaveCount { get; private set; }
    public int NotificationsSaveCount { get; private set; }

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
        Snapshot = Snapshot with { Settings = settings };
        SnapshotChanged?.Invoke(this, Snapshot);
    }

    public void SaveTransportConfig(TransportConfig config)
    {
        TransportSaveCount += 1;
        Snapshot = Snapshot with
        {
            Configuration = Snapshot.Configuration with { Transport = config }
        };
        SnapshotChanged?.Invoke(this, Snapshot);
    }

    public void SaveSecurityConfig(SecurityConfig config)
    {
        Snapshot = Snapshot with
        {
            Configuration = Snapshot.Configuration with { Security = config }
        };
        SnapshotChanged?.Invoke(this, Snapshot);
    }

    public void SaveTelemetryPolicy(TelemetryPolicyConfig config)
    {
        Snapshot = Snapshot with
        {
            Configuration = Snapshot.Configuration with { TelemetryPolicy = config }
        };
        SnapshotChanged?.Invoke(this, Snapshot);
    }

    public void SaveNotificationConfig(NotificationPolicyConfig config)
    {
        NotificationsSaveCount += 1;
        Snapshot = Snapshot with
        {
            Configuration = Snapshot.Configuration with { Notifications = config }
        };
        SnapshotChanged?.Invoke(this, Snapshot);
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

    public void HardResetPairing()
    {
    }

    public void ResetUiSession()
    {
    }

    public void Dispose()
    {
    }
}
