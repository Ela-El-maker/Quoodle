using System.Collections.ObjectModel;
using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class ActivityDiagnosticsViewModel : ObservableObject
{
    private readonly AgentStateStore _store;
    private string _selectedFilter = "All";

    public ActivityDiagnosticsViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += (_, s) => Apply(s);
        Entries = new ObservableCollection<ActivityEntry>();
        Filters = new[] { "All", "Info", "Warning", "Error" };
        Apply(_store.Snapshot);
    }

    public ObservableCollection<ActivityEntry> Entries { get; }

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

    private void Apply(AgentStateSnapshot snapshot)
    {
        Entries.Clear();

        IEnumerable<ActivityEntry> source = snapshot.Activity;
        source = SelectedFilter switch
        {
            "Info" => source.Where(x => x.Severity == ActivitySeverity.Info),
            "Warning" => source.Where(x => x.Severity == ActivitySeverity.Warning),
            "Error" => source.Where(x => x.Severity == ActivitySeverity.Error),
            _ => source
        };

        foreach (var entry in source)
        {
            Entries.Add(entry);
        }
    }
}
