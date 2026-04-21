using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Win32;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using Quoodle.Agent.UiCompanion.Views;
using System.Collections.Generic;
using System.Linq;

namespace Quoodle.Agent.UiCompanion;

public sealed partial class MainWindow : Window
{
    private const string NavPreferenceFileName = "nav-route.txt";
    private static readonly HashSet<string> CoreRoutes = new(StringComparer.OrdinalIgnoreCase)
    {
        "overview",
        "dashboard",
        "quick-status",
        "activity",
        "settings",
        "onboarding"
    };
    private readonly AgentStateStore _stateStore;
    private readonly string _navPreferencePath;

    public MainWindow()
    {
        InitializeComponent();
        ApplySystemBackdrop();
        ApplySystemTheme();

        _stateStore = App.StateStore;
        _navPreferencePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "QuoodleAgentUiCompanion",
            NavPreferenceFileName);
        _stateStore.SnapshotChanged += HandleSnapshotChanged;

        AppNav.Loaded += (_, _) =>
        {
            UpdatePaneVisualState(AppNav.DisplayMode);
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

    private void ApplySystemBackdrop()
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000))
        {
            return;
        }

        try
        {
            var backdropProperty = GetType().GetProperty("SystemBackdrop");
            if (backdropProperty is null || !backdropProperty.CanWrite)
            {
                return;
            }

            var micaType = GetType().Assembly.GetType("Microsoft.UI.Xaml.Media.MicaBackdrop")
                ?? Type.GetType("Microsoft.UI.Xaml.Media.MicaBackdrop, Microsoft.WinUI");
            if (micaType is null)
            {
                return;
            }

            var micaInstance = Activator.CreateInstance(micaType);
            if (micaInstance is null)
            {
                return;
            }

            backdropProperty.SetValue(this, micaInstance);
        }
        catch
        {
            // Backdrop APIs are best-effort; keep a solid shell if unavailable.
        }
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
        if (string.IsNullOrWhiteSpace(preferred))
        {
            return "overview";
        }

        return CoreRoutes.Contains(preferred) ? NormalizeRoute(preferred) : "overview";
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
    }

    private void RenderHeader(AgentStateSnapshot snapshot)
    {
        HeaderConnectionText.Text = snapshot.Connection switch
        {
            ConnectionState.Connected => "Connected",
            ConnectionState.Reconnecting => "Reconnecting",
            ConnectionState.Offline => "Offline",
            ConnectionState.AuthFailed => "Auth Failed",
            _ => "Connecting"
        };

        HeaderSessionText.Text = $"SESSION {snapshot.DeviceId}";
        HeaderDeviceText.Text = snapshot.DeviceName;
        HeaderHeartbeatText.Text = $"Last heartbeat {FormatAge(snapshot.LastHeartbeatUtc)} ago";

        HeaderVersionText.Text = $"v{snapshot.AgentVersion}";
        HeaderBuildText.Text = Environment.OSVersion.Version.ToString();
        HeaderPolicyText.Text = snapshot.Settings.BackgroundSync ? "Policy active" : "Policy paused";
        HeaderLatencyText.Text = $"{snapshot.LatencyMs} ms";

        FlyoutDeviceText.Text = snapshot.DeviceName;
        FlyoutVersionText.Text = $"v{snapshot.AgentVersion}";
        FlyoutPolicyText.Text = HeaderPolicyText.Text;
        FlyoutSessionText.Text = snapshot.DeviceId;

        PaneVersionText.Text = $"v{snapshot.AgentVersion}";

        var toneBrush = BrushOf(ResolveConnectionBrushKey(snapshot.Connection));
        ConnectionDot.Fill = toneBrush;
        ConnectionBadge.BorderBrush = toneBrush;
        HeaderConnectionText.Foreground = toneBrush;
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

        return ElementTheme.Default;
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

        route = NormalizeRoute(route);
        if (!_stateStore.Snapshot.IsPaired && route != "onboarding")
        {
            route = "onboarding";
            SelectNavItem(route);
        }

        Navigate(route);
        SavePreferredRoute(route);

        if (AppNav.DisplayMode != NavigationViewDisplayMode.Expanded && AppNav.IsPaneOpen)
        {
            AppNav.IsPaneOpen = false;
        }
    }

    private void OnPaneDisplayModeChanged(NavigationView sender, NavigationViewDisplayModeChangedEventArgs args)
    {
        UpdatePaneVisualState(args.DisplayMode);
    }

    private void Navigate(string route)
    {
        route = NormalizeRoute(route);
        var pageType = route switch
        {
            "onboarding" => typeof(OnboardingPage),
            "overview" => typeof(DashboardPage),
            "device-details" => typeof(DeviceDetailsPage),
            "command-history" => typeof(CommandHistoryPage),
            "pairing-recovery" => typeof(PairingRecoveryPage),
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
        if (ContentFrame.CurrentSourcePageType == typeof(QuickStatusPage)) return "overview";
        if (ContentFrame.CurrentSourcePageType == typeof(ActivityDiagnosticsPage)) return "activity";
        if (ContentFrame.CurrentSourcePageType == typeof(SettingsPage)) return "settings";
        return "overview";
    }

    private void SelectNavItem(string route)
    {
        route = NormalizeRoute(route);
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
        route = NormalizeRoute(route);
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

    private string NormalizeRoute(string route)
    {
        if (string.Equals(route, "dashboard", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(route, "quick-status", StringComparison.OrdinalIgnoreCase))
        {
            return "overview";
        }

        return route;
    }

    private Brush BrushOf(string key)
    {
        if (Application.Current.Resources.TryGetValue(key, out var appObj) && appObj is Brush appBrush)
        {
            return appBrush;
        }

        return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    private static string ResolveConnectionBrushKey(ConnectionState state)
    {
        return state switch
        {
            ConnectionState.Connected => "SuccessBrush",
            ConnectionState.Reconnecting => "WarningBrush",
            ConnectionState.Offline => "DangerBrush",
            ConnectionState.AuthFailed => "DangerBrush",
            _ => "InfoBrush"
        };
    }

    private void UpdatePaneVisualState(NavigationViewDisplayMode mode)
    {
        var expanded = mode == NavigationViewDisplayMode.Expanded;
        PaneBrandDetails.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
        PaneVersionText.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
        MonitorHeader.Visibility = expanded ? Visibility.Visible : Visibility.Collapsed;
        PaneBrandRoot.Padding = expanded ? new Thickness(8, 6, 8, 6) : new Thickness(7, 6, 7, 6);
    }
}
