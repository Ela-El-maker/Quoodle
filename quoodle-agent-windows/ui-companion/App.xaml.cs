using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.Services;
using System.Runtime.InteropServices;
using System.Text;
using WinRT.Interop;

namespace Quoodle.Agent.UiCompanion;

public partial class App : Application
{
    private Window? _window;

    public static IAgentStateProvider StateProvider { get; } = CreateStateProvider();
    public static AgentStateStore StateStore { get; } = new(StateProvider);
    public static Window? MainWindowInstance { get; private set; }
    public static IntPtr MainWindowHandle => MainWindowInstance is null ? IntPtr.Zero : WindowNative.GetWindowHandle(MainWindowInstance);

    public App()
    {
        InitializeComponent();
        StateStore.BindUiContext(SynchronizationContext.Current);
        StateProvider.Start();
        UnhandledException += OnUnhandledException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            MainWindowInstance = _window;
            _window.Activate();
        }
        catch (Exception ex)
        {
            ReportFatalError("Startup failure while creating MainWindow", ex);
        }
    }

    private static void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        ReportFatalError("Unhandled UI exception", e.Exception);
        e.Handled = true;
    }

    private static void ReportFatalError(string context, Exception ex)
    {
        var details = BuildErrorDetails(context, ex);
        WriteErrorLog(details);
        ShowFatalErrorDialog(details);

#if DEBUG
        try
        {
            var window = new Window
            {
                Title = "Quoodle UI Startup Error"
            };

            window.Content = new ScrollViewer
            {
                Content = new TextBlock
                {
                    Text = details,
                    TextWrapping = TextWrapping.Wrap,
                    FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
                    Margin = new Thickness(16)
                }
            };

            window.Activate();
        }
        catch
        {
            // Last resort: avoid recursive failures in exception handling.
        }
#endif
    }

    [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    private static void ShowFatalErrorDialog(string details)
    {
        try
        {
            const uint mbIconError = 0x10;
            const uint mbOk = 0x0;
            _ = MessageBox(IntPtr.Zero, details, "Quoodle UI Startup Error", mbOk | mbIconError);
        }
        catch
        {
            // Best effort only.
        }
    }

    private static string BuildErrorDetails(string context, Exception ex)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Quoodle Agent UI failed to render.");
        sb.AppendLine();
        sb.AppendLine($"Context: {context}");
        sb.AppendLine($"Time (UTC): {DateTimeOffset.UtcNow:O}");
        sb.AppendLine();
        sb.AppendLine(ex.ToString());
        sb.AppendLine();
        sb.AppendLine($"Log path: {GetErrorLogPath()}");
        return sb.ToString();
    }

    private static void WriteErrorLog(string details)
    {
        try
        {
            var logPath = GetErrorLogPath();
            var dir = Path.GetDirectoryName(logPath);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            File.WriteAllText(logPath, details);
        }
        catch
        {
            // Best effort only.
        }
    }

    private static string GetErrorLogPath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "QuoodleAgentUiCompanion",
            "startup-error.log");
    }

    private static IAgentStateProvider CreateStateProvider()
    {
        if (ReadBoolEnv("QUOODLE_UI_USE_MOCK", false))
        {
            return new MockAgentStateProvider();
        }

        try
        {
            return new UiBridgeProvider();
        }
        catch
        {
            // Fall back to mock mode if the runtime bridge cannot initialize.
            return new MockAgentStateProvider();
        }
    }

    private static bool ReadBoolEnv(string key, bool fallback)
    {
        var raw = Environment.GetEnvironmentVariable(key);
        if (string.IsNullOrWhiteSpace(raw))
        {
            return fallback;
        }

        var normalized = raw.Trim().ToLowerInvariant();
        return normalized is "1" or "true" or "yes" or "on";
    }

}
