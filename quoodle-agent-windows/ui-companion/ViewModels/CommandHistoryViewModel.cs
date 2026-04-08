using System.Collections.ObjectModel;
using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class CommandHistoryViewModel : ObservableObject
{
    private readonly AgentStateStore _store;
    private string _selectedFilter = "All";
    private string _searchText = string.Empty;

    public CommandHistoryViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += (_, snapshot) => Apply(snapshot);

        Entries = new ObservableCollection<CommandHistoryItem>();
        Filters = new[] { "All", "Active", "Succeeded", "Failed" };
        Apply(_store.Snapshot);
    }

    public ObservableCollection<CommandHistoryItem> Entries { get; }

    public IReadOnlyList<string> Filters { get; }

    public string SelectedFilter
    {
        get => _selectedFilter;
        set
        {
            if (SetProperty(ref _selectedFilter, value))
            {
                Apply(_store.Snapshot);
            }
        }
    }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetProperty(ref _searchText, value))
            {
                Apply(_store.Snapshot);
            }
        }
    }

    private void Apply(AgentStateSnapshot snapshot)
    {
        Entries.Clear();

        IEnumerable<CommandExecutionEntry> source = snapshot.CommandHistory;
        source = SelectedFilter switch
        {
            "Active" => source.Where(x => x.Status is CommandExecutionStatus.Queued or CommandExecutionStatus.Dispatched or CommandExecutionStatus.Executing),
            "Succeeded" => source.Where(x => x.Status == CommandExecutionStatus.Succeeded),
            "Failed" => source.Where(x => x.Status is CommandExecutionStatus.Failed or CommandExecutionStatus.TimedOut or CommandExecutionStatus.Rejected),
            _ => source
        };

        var query = SearchText.Trim();
        if (!string.IsNullOrWhiteSpace(query))
        {
            source = source.Where(x =>
                x.Command.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                x.Source.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                x.Status.ToString().Contains(query, StringComparison.OrdinalIgnoreCase) ||
                x.Id.Contains(query, StringComparison.OrdinalIgnoreCase));
        }

        foreach (var entry in source)
        {
            Entries.Add(new CommandHistoryItem
            {
                Id = entry.Id,
                IssuedAt = entry.IssuedAtUtc.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"),
                Command = entry.Command,
                Status = entry.Status.ToString(),
                Tone = ResolveTone(entry.Status),
                Source = entry.Source,
                Duration = entry.DurationMs <= 0 ? "--" : $"{entry.DurationMs} ms",
                Error = string.IsNullOrWhiteSpace(entry.ErrorMessage) ? "None" : entry.ErrorMessage
            });
        }
    }

    private static string ResolveTone(CommandExecutionStatus status)
    {
        return status switch
        {
            CommandExecutionStatus.Succeeded => "Success",
            CommandExecutionStatus.Failed => "Danger",
            CommandExecutionStatus.Rejected => "Danger",
            CommandExecutionStatus.TimedOut => "Warning",
            CommandExecutionStatus.Executing => "Info",
            CommandExecutionStatus.Dispatched => "Info",
            CommandExecutionStatus.Queued => "Neutral",
            _ => "Neutral"
        };
    }
}

public sealed class CommandHistoryItem
{
    public string Id { get; init; } = string.Empty;

    public string IssuedAt { get; init; } = string.Empty;

    public string Command { get; init; } = string.Empty;

    public string Status { get; init; } = string.Empty;

    public string Tone { get; init; } = "Neutral";

    public string Source { get; init; } = string.Empty;

    public string Duration { get; init; } = "--";

    public string Error { get; init; } = "None";
}
