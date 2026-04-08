using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Quoodle.Agent.UiCompanion.Services;
using System.Text;

namespace Quoodle.Agent.UiCompanion;

public partial class App : Application
{
    private Window? _window;

    public static IAgentStateProvider StateProvider { get; } = new MockAgentStateProvider();
    public static AgentStateStore StateStore { get; } = new(StateProvider);

    public App()
    {
        InitializeComponent();
        StateProvider.Start();
        UnhandledException += OnUnhandledException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
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

}
