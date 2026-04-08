namespace Quoodle.Agent.UiCompanion.Models;

public sealed record CommandExecutionEntry(
    string Id,
    DateTimeOffset IssuedAtUtc,
    string Command,
    CommandExecutionStatus Status,
    string Source,
    int DurationMs,
    string ErrorMessage);
