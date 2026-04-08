namespace Quoodle.Agent.UiCompanion.Models;

public sealed record UiSettings(
    bool NotifyInfo,
    bool NotifyWarningsAndCritical,
    bool BackgroundSync,
    bool CollectDiagnostics,
    bool StartWithWindows,
    bool AllowTrayNotifications)
{
    public static UiSettings Default { get; } = new(
        NotifyInfo: false,
        NotifyWarningsAndCritical: true,
        BackgroundSync: true,
        CollectDiagnostics: true,
        StartWithWindows: true,
        AllowTrayNotifications: true);
}
