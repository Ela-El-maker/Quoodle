namespace Quoodle.Agent.UiCompanion.Models;

public sealed record ActivityEntry(
    DateTimeOffset Timestamp,
    ActivitySeverity Severity,
    string Source,
    string Title,
    string Details);
