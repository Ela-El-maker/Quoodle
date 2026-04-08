using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Win32;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using Quoodle.Agent.UiCompanion.Views;
using System.Linq;

namespace Quoodle.Agent.UiCompanion;

public sealed partial class MainWindow : Window
{
    private const string NavPreferenceFileName = "nav-route.txt";
    private readonly AgentStateStore _stateStore;
    private readonly string _navPreferencePath;

    public MainWindow()
    {
        InitializeComponent();
        ApplySystemTheme();

        _stateStore = App.StateStore;
        _navPreferencePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "QuoodleAgentUiCompanion",
            NavPreferenceFileName);
        _stateStore.SnapshotChanged += HandleSnapshotChanged;

        AppNav.Loaded += (_, _) =>
        {
            var route = ResolveInitialRoute(_stateStore.Snapshot);
            Navigate(route);
            SelectNavItem(route);
            RenderHeader(_stateStore.Snapshot);
        };
        ContentFrame.Navigated += (_, _) =>
        {
            var route = CurrentRoute();
            SelectNavItem(route);
            SavePreferredRoute(route);
        };

        Closed += (_, _) => _stateStore.SnapshotChanged -= HandleSnapshotChanged;
    }

    private void ApplySystemTheme()
    {
        if (Content is not FrameworkElement root)
        {
            return;
        }

        root.RequestedTheme = ResolveSystemTheme();
    }

    private string ResolveInitialRoute(AgentStateSnapshot snapshot)
    {
        if (!snapshot.IsPaired)
        {
            return "onboarding";
        }

        var preferred = LoadPreferredRoute();
        return string.IsNullOrWhiteSpace(preferred) ? "dashboard" : preferred;
    }

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        if (!DispatcherQueue.HasThreadAccess)
        {
            _ = DispatcherQueue.TryEnqueue(() => HandleSnapshotChanged(sender, snapshot));
            return;
        }

        RenderHeader(snapshot);

        if (!snapshot.IsPaired && CurrentRoute() != "onboarding")
        {
            Navigate("onboarding");
            SelectNavItem("onboarding");
            return;
        }

        if (snapshot.IsPaired && CurrentRoute() == "onboarding")
        {
            Navigate("dashboard");
            SelectNavItem("dashboard");
        }
    }

    private void RenderHeader(AgentStateSnapshot snapshot)
    {
        HeaderConnectionText.Text = snapshot.Connection switch
        {
            ConnectionState.Connected => $"Connected • {snapshot.Health}",
            ConnectionState.Reconnecting => "Reconnecting",
            ConnectionState.Offline => "Offline",
            ConnectionState.AuthFailed => "Auth Failed",
            _ => "Connecting"
        };

        HeaderSessionText.Text = $"SESSION {snapshot.DeviceId}";
        HeaderDeviceText.Text = $"DEVICE {snapshot.DeviceName}";
        HeaderHeartbeatText.Text = $"Last heartbeat {FormatAge(snapshot.LastHeartbeatUtc)} ago";

        HeaderVersionText.Text = snapshot.AgentVersion;
        HeaderBuildText.Text = Environment.OSVersion.Version.ToString();
        HeaderPolicyText.Text = snapshot.Settings.BackgroundSync ? "policy:active" : "policy:paused";
        HeaderLatencyText.Text = $"{snapshot.LatencyMs} ms";

        PaneVersionText.Text = $"v{snapshot.AgentVersion} • {snapshot.DeviceName}";

        StatusLine1.Text = snapshot.Connection switch
        {
            ConnectionState.Connected => "WSS Connected",
            ConnectionState.Reconnecting => "WSS Reconnecting",
            ConnectionState.Offline => "WSS Offline",
            ConnectionState.AuthFailed => "WSS Auth Failed",
            _ => "WSS Connecting"
        };
        StatusLine2.Text = snapshot.Settings.CollectDiagnostics ? "Kernel Guard Active" : "Kernel Guard Standby";
        StatusLine3.Text = snapshot.Health switch
        {
            HealthState.Healthy => "Policy Matched",
            HealthState.Warning => "Policy Warning",
            _ => "Policy Attention Needed"
        };

        var pendingCount = snapshot.CommandHistory.Count(c => c.Status is CommandExecutionStatus.Queued or CommandExecutionStatus.Dispatched or CommandExecutionStatus.Executing);
        KernelHintText.Text = $"{pendingCount} command events pending review";
    }

    private static ElementTheme ResolveSystemTheme()
    {
        try
        {
            using var personalizeKey = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
                writable: false);

            if (personalizeKey?.GetValue("AppsUseLightTheme") is int themeFlag)
            {
                return themeFlag == 0 ? ElementTheme.Dark : ElementTheme.Light;
            }
        }
        catch
        {
            // Fall through to a readable default if probing fails.
        }

        return ElementTheme.Dark;
    }

    private static string FormatAge(DateTimeOffset timestamp)
    {
        var age = DateTimeOffset.UtcNow - timestamp;
        if (age.TotalSeconds < 60) return $"{Math.Max(1, (int)age.TotalSeconds)}s";
        if (age.TotalMinutes < 60) return $"{(int)age.TotalMinutes}m";
        return $"{(int)age.TotalHours}h";
    }

    private void OnSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string route)
        {
            return;
        }

        if (!_stateStore.Snapshot.IsPaired && route != "onboarding")
        {
            route = "onboarding";
            SelectNavItem(route);
        }

        Navigate(route);
        SavePreferredRoute(route);
    }

    private void Navigate(string route)
    {
        var pageType = route switch
        {
            "onboarding" => typeof(OnboardingPage),
            "dashboard" => typeof(DashboardPage),
            "device-details" => typeof(DeviceDetailsPage),
            "command-history" => typeof(CommandHistoryPage),
            "pairing-recovery" => typeof(PairingRecoveryPage),
            "quick-status" => typeof(QuickStatusPage),
            "activity" => typeof(ActivityDiagnosticsPage),
            "settings" => typeof(SettingsPage),
            _ => typeof(DashboardPage)
        };

        if (ContentFrame.CurrentSourcePageType != pageType)
        {
            _ = ContentFrame.Navigate(pageType);
        }
    }

    private string CurrentRoute()
    {
        if (ContentFrame.CurrentSourcePageType == typeof(OnboardingPage)) return "onboarding";
        if (ContentFrame.CurrentSourcePageType == typeof(DeviceDetailsPage)) return "device-details";
        if (ContentFrame.CurrentSourcePageType == typeof(CommandHistoryPage)) return "command-history";
        if (ContentFrame.CurrentSourcePageType == typeof(PairingRecoveryPage)) return "pairing-recovery";
        if (ContentFrame.CurrentSourcePageType == typeof(QuickStatusPage)) return "quick-status";
        if (ContentFrame.CurrentSourcePageType == typeof(ActivityDiagnosticsPage)) return "activity";
        if (ContentFrame.CurrentSourcePageType == typeof(SettingsPage)) return "settings";
        return "dashboard";
    }

    private void SelectNavItem(string route)
    {
        var item = AppNav.MenuItems
            .OfType<NavigationViewItem>()
            .FirstOrDefault(x => string.Equals(x.Tag as string, route, StringComparison.OrdinalIgnoreCase));

        if (item is not null)
        {
            AppNav.SelectedItem = item;
        }
    }

    private string? LoadPreferredRoute()
    {
        try
        {
            if (!File.Exists(_navPreferencePath))
            {
                return null;
            }

            return File.ReadAllText(_navPreferencePath).Trim();
        }
        catch
        {
            return null;
        }
    }

    private void SavePreferredRoute(string route)
    {
        try
        {
            var dir = Path.GetDirectoryName(_navPreferencePath);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            File.WriteAllText(_navPreferencePath, route);
        }
        catch
        {
            // Preference persistence is best-effort only.
        }
    }
}
