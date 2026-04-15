using Microsoft.UI.Xaml;
using Microsoft.Windows.ApplicationModel.DynamicDependency;
using System.Runtime.InteropServices;
using System.Text;

namespace Quoodle.Agent.UiCompanion;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            InitializeWindowsAppSdk();
            Application.Start(static _ =>
            {
                var context = new Microsoft.UI.Dispatching.DispatcherQueueSynchronizationContext(
                    Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                var app = new App();
            });
        }
        catch (Exception ex)
        {
            WriteStartupError(ex);
            ShowStartupErrorDialog(ex);
            Environment.Exit(1);
        }
        finally
        {
            try
            {
                Bootstrap.Shutdown();
            }
            catch
            {
                // no-op: startup failed before bootstrap was initialized.
            }
        }
    }

    private static void InitializeWindowsAppSdk()
    {
        // Try known 1.x channels in descending order, then a generic 1.x probe.
        var probes = new[]
        {
            0x00010008u,
            0x00010007u,
            0x00010006u,
            0x00010005u,
            0x00010000u
        };

        var errors = new List<int>();
        foreach (var probe in probes)
        {
            if (Bootstrap.TryInitialize(
                    probe,
                    string.Empty,
                    new PackageVersion(0),
                    Bootstrap.InitializeOptions.None,
                    out var hr))
            {
                return;
            }

            errors.Add(hr);
        }

        var combined = string.Join(", ", errors.Select(static hr => $"0x{hr:X8}"));
        throw new COMException($"Windows App SDK bootstrap failed for all probes. HRESULTs: {combined}");
    }

    private static void WriteStartupError(Exception ex)
    {
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "QuoodleAgentUiCompanion");
            Directory.CreateDirectory(dir);

            var sb = new StringBuilder();
            sb.AppendLine($"UTC: {DateTimeOffset.UtcNow:O}");
            sb.AppendLine(ex.ToString());
            File.WriteAllText(Path.Combine(dir, "program-startup-error.log"), sb.ToString());
        }
        catch
        {
            // no-op
        }
    }

    [DllImport("user32.dll", EntryPoint = "MessageBoxW", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    private static void ShowStartupErrorDialog(Exception ex)
    {
        try
        {
            var logPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "QuoodleAgentUiCompanion",
                "program-startup-error.log");
            var message =
                "Quoodle Agent UI failed to start.\n\n" +
                ex.Message +
                "\n\nSee log:\n" +
                logPath;
            const uint mbIconError = 0x10;
            const uint mbOk = 0x0;
            _ = MessageBox(IntPtr.Zero, message, "Quoodle Agent UI", mbOk | mbIconError);
        }
        catch
        {
            // no-op
        }
    }
}
