using System.Collections.ObjectModel;
using System.Text;
using System.Text.Json;
using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public enum ActivityDiagnosticsTab
{
    WssMessageLog,
    CommandHistory,
    KernelEvents
}

public sealed record WssMessageLogRowView(
    string Seq,
    string Type,
    string TypeTone,
    string From,
    string FromTone,
    string MessageId,
    string Timestamp,
    string BodySummary,
    string SigLabel,
    string SigTone,
    string RawJson);

public sealed record CommandHistoryRowView(
    string CommandId,
    string Method,
    string MethodTone,
    string Priority,
    string PriorityTone,
    string State,
    string StateTone,
    string ExecPath,
    string KernelExecId,
    string IssuedAt,
    string Duration,
    string OriginUser,
    string RawJson);

public sealed record KernelEventRowView(
    string EventId,
    string EventType,
    string Opcode,
    string OpcodeTone,
    string Status,
    string StatusTone,
    string ErrorCode,
    string KernelExecId,
    string AgentSeq,
    string CommandId,
    string Timestamp,
    string RawJson);

internal sealed class TabQueryState
{
    public required string SortColumn { get; set; }

    public bool SortDescending { get; set; }

    public string SearchQuery { get; set; } = string.Empty;

    public string Filter1 { get; set; } = string.Empty;

    public string Filter2 { get; set; } = string.Empty;

    public string Filter3 { get; set; } = string.Empty;

    public int PageIndex { get; set; }
}

public sealed class ActivityDiagnosticsViewModel : ObservableObject, IDisposable
{
    private const int PageSize = 10;
    private static readonly JsonSerializerOptions JsonPretty = new() { WriteIndented = true };

    private readonly AgentStateStore _store;
    private readonly Dictionary<ActivityDiagnosticsTab, TabQueryState> _tabState;

    private AgentStateSnapshot _snapshot = AgentStateSnapshot.CreateInitial();
    private ActivityDiagnosticsTab _activeTab = ActivityDiagnosticsTab.WssMessageLog;
    private bool _filter3Visible = true;

    private IReadOnlyList<string> _filter1Options = Array.Empty<string>();
    private IReadOnlyList<string> _filter2Options = Array.Empty<string>();
    private IReadOnlyList<string> _filter3Options = Array.Empty<string>();
    private string _searchPlaceholder = "Search";
    private string _selectedFilter1 = string.Empty;
    private string _selectedFilter2 = string.Empty;
    private string _selectedFilter3 = string.Empty;
    private string _searchQuery = string.Empty;

    private int _wssCount;
    private int _commandCount;
    private int _kernelCount;
    private string _tableFooter = "0 rows";
    private string _pagePill = "1";
    private bool _canPrevPage;
    private bool _canNextPage;

    private string _rawMessageJson = string.Empty;
    private bool _hasRawSelection;
    private string _rawSizeText = "0 chars · 0 bytes";

    private IReadOnlyList<WssMessageLogRow> _currentWssPageSource = Array.Empty<WssMessageLogRow>();
    private IReadOnlyList<CommandHistoryRow> _currentCommandPageSource = Array.Empty<CommandHistoryRow>();
    private IReadOnlyList<KernelEventRow> _currentKernelPageSource = Array.Empty<KernelEventRow>();

    public ActivityDiagnosticsViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += HandleSnapshotChanged;

        _tabState = new()
        {
            [ActivityDiagnosticsTab.WssMessageLog] = new TabQueryState
            {
                SortColumn = "seq",
                SortDescending = true,
                Filter1 = "All Types",
                Filter2 = "All Sources",
                Filter3 = "All Sig States"
            },
            [ActivityDiagnosticsTab.CommandHistory] = new TabQueryState
            {
                SortColumn = "issued_at",
                SortDescending = true,
                Filter1 = "All States",
                Filter2 = "All Methods",
                Filter3 = "All Paths"
            },
            [ActivityDiagnosticsTab.KernelEvents] = new TabQueryState
            {
                SortColumn = "event_id",
                SortDescending = true,
                Filter1 = "All Statuses",
                Filter2 = "All Opcodes",
                Filter3 = string.Empty
            }
        };

        WssRows = new ObservableCollection<WssMessageLogRowView>();
        CommandRows = new ObservableCollection<CommandHistoryRowView>();
        KernelRows = new ObservableCollection<KernelEventRowView>();

        _snapshot = store.Snapshot;
        Rebuild();
    }

    public ObservableCollection<WssMessageLogRowView> WssRows { get; }

    public ObservableCollection<CommandHistoryRowView> CommandRows { get; }

    public ObservableCollection<KernelEventRowView> KernelRows { get; }

    public ActivityDiagnosticsTab ActiveTab
    {
        get => _activeTab;
        private set => SetProperty(ref _activeTab, value);
    }

    public bool IsWssTab => ActiveTab == ActivityDiagnosticsTab.WssMessageLog;

    public bool IsCommandTab => ActiveTab == ActivityDiagnosticsTab.CommandHistory;

    public bool IsKernelTab => ActiveTab == ActivityDiagnosticsTab.KernelEvents;

    public bool Filter3Visible
    {
        get => _filter3Visible;
        private set => SetProperty(ref _filter3Visible, value);
    }

    public IReadOnlyList<string> Filter1Options
    {
        get => _filter1Options;
        private set => SetProperty(ref _filter1Options, value);
    }

    public IReadOnlyList<string> Filter2Options
    {
        get => _filter2Options;
        private set => SetProperty(ref _filter2Options, value);
    }

    public IReadOnlyList<string> Filter3Options
    {
        get => _filter3Options;
        private set => SetProperty(ref _filter3Options, value);
    }

    public string SearchPlaceholder
    {
        get => _searchPlaceholder;
        private set => SetProperty(ref _searchPlaceholder, value);
    }

    public string SelectedFilter1
    {
        get => _selectedFilter1;
        private set => SetProperty(ref _selectedFilter1, value);
    }

    public string SelectedFilter2
    {
        get => _selectedFilter2;
        private set => SetProperty(ref _selectedFilter2, value);
    }

    public string SelectedFilter3
    {
        get => _selectedFilter3;
        private set => SetProperty(ref _selectedFilter3, value);
    }

    public string SearchQuery
    {
        get => _searchQuery;
        private set => SetProperty(ref _searchQuery, value);
    }

    public int WssCount
    {
        get => _wssCount;
        private set => SetProperty(ref _wssCount, value);
    }

    public int CommandCount
    {
        get => _commandCount;
        private set => SetProperty(ref _commandCount, value);
    }

    public int KernelCount
    {
        get => _kernelCount;
        private set => SetProperty(ref _kernelCount, value);
    }

    public string TableFooter
    {
        get => _tableFooter;
        private set => SetProperty(ref _tableFooter, value);
    }

    public string PagePill
    {
        get => _pagePill;
        private set => SetProperty(ref _pagePill, value);
    }

    public bool CanPrevPage
    {
        get => _canPrevPage;
        private set => SetProperty(ref _canPrevPage, value);
    }

    public bool CanNextPage
    {
        get => _canNextPage;
        private set => SetProperty(ref _canNextPage, value);
    }

    public string RawMessageJson
    {
        get => _rawMessageJson;
        private set => SetProperty(ref _rawMessageJson, value);
    }

    public bool HasRawSelection
    {
        get => _hasRawSelection;
        private set => SetProperty(ref _hasRawSelection, value);
    }

    public string RawSizeText
    {
        get => _rawSizeText;
        private set => SetProperty(ref _rawSizeText, value);
    }

    public void SelectTab(ActivityDiagnosticsTab tab)
    {
        if (ActiveTab == tab)
        {
            return;
        }

        ActiveTab = tab;
        RaisePropertyChanged(nameof(IsWssTab));
        RaisePropertyChanged(nameof(IsCommandTab));
        RaisePropertyChanged(nameof(IsKernelTab));
        Rebuild();
    }

    public void SetSearch(string value)
    {
        var state = _tabState[ActiveTab];
        state.SearchQuery = value?.Trim() ?? string.Empty;
        state.PageIndex = 0;
        Rebuild();
    }

    public void SetFilter1(string value)
    {
        var state = _tabState[ActiveTab];
        state.Filter1 = string.IsNullOrWhiteSpace(value) ? state.Filter1 : value;
        state.PageIndex = 0;
        Rebuild();
    }

    public void SetFilter2(string value)
    {
        var state = _tabState[ActiveTab];
        state.Filter2 = string.IsNullOrWhiteSpace(value) ? state.Filter2 : value;
        state.PageIndex = 0;
        Rebuild();
    }

    public void SetFilter3(string value)
    {
        if (!Filter3Visible)
        {
            return;
        }

        var state = _tabState[ActiveTab];
        state.Filter3 = string.IsNullOrWhiteSpace(value) ? state.Filter3 : value;
        state.PageIndex = 0;
        Rebuild();
    }

    public void ToggleSort(string column)
    {
        if (string.IsNullOrWhiteSpace(column))
        {
            return;
        }

        var state = _tabState[ActiveTab];
        if (string.Equals(state.SortColumn, column, StringComparison.OrdinalIgnoreCase))
        {
            state.SortDescending = !state.SortDescending;
        }
        else
        {
            state.SortColumn = column;
            state.SortDescending = true;
        }

        state.PageIndex = 0;
        Rebuild();
    }

    public bool IsSortColumn(string column) => string.Equals(_tabState[ActiveTab].SortColumn, column, StringComparison.OrdinalIgnoreCase);

    public bool IsSortDescending() => _tabState[ActiveTab].SortDescending;

    public void PrevPage()
    {
        var state = _tabState[ActiveTab];
        if (state.PageIndex <= 0)
        {
            return;
        }

        state.PageIndex -= 1;
        Rebuild();
    }

    public void NextPage()
    {
        var state = _tabState[ActiveTab];
        if (!CanNextPage)
        {
            return;
        }

        state.PageIndex += 1;
        Rebuild();
    }

    public void SelectWssRow(WssMessageLogRowView? row) => SetRawMessage(row?.RawJson);

    public void SelectCommandRow(CommandHistoryRowView? row) => SetRawMessage(row?.RawJson);

    public void SelectKernelRow(KernelEventRowView? row) => SetRawMessage(row?.RawJson);

    public void ClearRawMessage() => SetRawMessage(null);

    public string BuildCurrentViewExportJson()
    {
        var state = _tabState[ActiveTab];

        object rows = ActiveTab switch
        {
            ActivityDiagnosticsTab.WssMessageLog => _currentWssPageSource,
            ActivityDiagnosticsTab.CommandHistory => _currentCommandPageSource,
            _ => _currentKernelPageSource
        };

        var payload = new
        {
            tab = ActiveTab.ToString(),
            generated_at = DateTimeOffset.Now.ToString("O"),
            query = new
            {
                search = state.SearchQuery,
                filter1 = state.Filter1,
                filter2 = state.Filter2,
                filter3 = state.Filter3,
                sort = state.SortColumn,
                descending = state.SortDescending
            },
            paging = new
            {
                page = state.PageIndex + 1,
                page_size = PageSize
            },
            rows
        };

        return JsonSerializer.Serialize(payload, JsonPretty);
    }

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        _snapshot = snapshot;
        Rebuild();
    }

    private void Rebuild()
    {
        WssCount = _snapshot.WssMessageLog.Count;
        CommandCount = _snapshot.CommandHistoryLog.Count;
        KernelCount = _snapshot.KernelEvents.Count;

        ConfigureTabFilters();
        RebuildCurrentTable();
    }

    private void ConfigureTabFilters()
    {
        var state = _tabState[ActiveTab];
        SearchQuery = state.SearchQuery;

        switch (ActiveTab)
        {
            case ActivityDiagnosticsTab.WssMessageLog:
                SearchPlaceholder = "Search type, message ID, summary";
                Filter1Options = BuildOptions(_snapshot.WssMessageLog.Select(x => x.Type), "All Types");
                Filter2Options = BuildOptions(_snapshot.WssMessageLog.Select(x => x.From), "All Sources");
                Filter3Options = BuildOptions(_snapshot.WssMessageLog.Select(x => x.SigState), "All Sig States");
                Filter3Visible = true;
                EnsureFilterSelection(state, Filter1Options, Filter2Options, Filter3Options, "All Types", "All Sources", "All Sig States");
                break;

            case ActivityDiagnosticsTab.CommandHistory:
                SearchPlaceholder = "Search command ID, trace ID, method, user";
                Filter1Options = BuildOptions(_snapshot.CommandHistoryLog.Select(x => x.State), "All States");
                Filter2Options = BuildOptions(_snapshot.CommandHistoryLog.Select(x => x.Method), "All Methods");
                Filter3Options = BuildOptions(_snapshot.CommandHistoryLog.Select(x => x.ExecPath), "All Paths");
                Filter3Visible = true;
                EnsureFilterSelection(state, Filter1Options, Filter2Options, Filter3Options, "All States", "All Methods", "All Paths");
                break;

            default:
                SearchPlaceholder = "Search event ID, opcode, request ID";
                Filter1Options = BuildOptions(_snapshot.KernelEvents.Select(x => x.Status), "All Statuses");
                Filter2Options = BuildOptions(_snapshot.KernelEvents.Select(x => x.Opcode), "All Opcodes");
                Filter3Options = Array.Empty<string>();
                Filter3Visible = false;
                EnsureFilterSelection(state, Filter1Options, Filter2Options, Filter3Options, "All Statuses", "All Opcodes", string.Empty);
                break;
        }

        SelectedFilter1 = state.Filter1;
        SelectedFilter2 = state.Filter2;
        SelectedFilter3 = state.Filter3;
    }

    private static IReadOnlyList<string> BuildOptions(IEnumerable<string?> source, string allLabel)
    {
        var items = source
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x!.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
            .ToList();
        items.Insert(0, allLabel);
        return items;
    }

    private static void EnsureFilterSelection(
        TabQueryState state,
        IReadOnlyList<string> f1,
        IReadOnlyList<string> f2,
        IReadOnlyList<string> f3,
        string fallback1,
        string fallback2,
        string fallback3)
    {
        if (!f1.Contains(state.Filter1))
        {
            state.Filter1 = fallback1;
        }

        if (!f2.Contains(state.Filter2))
        {
            state.Filter2 = fallback2;
        }

        if (f3.Count == 0)
        {
            state.Filter3 = string.Empty;
        }
        else if (!f3.Contains(state.Filter3))
        {
            state.Filter3 = fallback3;
        }
    }

    private void RebuildCurrentTable()
    {
        switch (ActiveTab)
        {
            case ActivityDiagnosticsTab.WssMessageLog:
                BuildWssPage();
                break;
            case ActivityDiagnosticsTab.CommandHistory:
                BuildCommandPage();
                break;
            default:
                BuildKernelPage();
                break;
        }
    }

    private void BuildWssPage()
    {
        var state = _tabState[ActiveTab];
        var filtered = _snapshot.WssMessageLog
            .Where(row =>
                MatchesSearch(state.SearchQuery, row.Type, row.MessageId, row.BodySummary, row.From) &&
                MatchesFilter(state.Filter1, "All Types", row.Type) &&
                MatchesFilter(state.Filter2, "All Sources", row.From) &&
                MatchesFilter(state.Filter3, "All Sig States", row.SigState));

        filtered = ApplyWssSort(filtered, state.SortColumn, state.SortDescending);
        var page = Paginate(filtered.ToList(), state, "messages", out var totalRows, out var totalPages);

        _currentWssPageSource = page;
        WssRows.Clear();
        foreach (var row in page)
        {
            WssRows.Add(MapWssRow(row));
        }

        ClearCollectionIfNeeded(CommandRows);
        ClearCollectionIfNeeded(KernelRows);

        UpdateFooter(totalRows, totalPages, state.PageIndex, "messages");
    }

    private void BuildCommandPage()
    {
        var state = _tabState[ActiveTab];
        var filtered = _snapshot.CommandHistoryLog
            .Where(row =>
                MatchesSearch(state.SearchQuery, row.CommandId, row.Method, row.KernelExecId, row.OriginUser) &&
                MatchesFilter(state.Filter1, "All States", row.State) &&
                MatchesFilter(state.Filter2, "All Methods", row.Method) &&
                MatchesFilter(state.Filter3, "All Paths", row.ExecPath));

        filtered = ApplyCommandSort(filtered, state.SortColumn, state.SortDescending);
        var page = Paginate(filtered.ToList(), state, "commands", out var totalRows, out var totalPages);

        _currentCommandPageSource = page;
        CommandRows.Clear();
        foreach (var row in page)
        {
            CommandRows.Add(MapCommandRow(row));
        }

        ClearCollectionIfNeeded(WssRows);
        ClearCollectionIfNeeded(KernelRows);

        UpdateFooter(totalRows, totalPages, state.PageIndex, "commands");
    }

    private void BuildKernelPage()
    {
        var state = _tabState[ActiveTab];
        var filtered = _snapshot.KernelEvents
            .Where(row =>
                MatchesSearch(state.SearchQuery, row.EventId?.ToString(), row.Opcode, row.KernelExecId, row.CommandId) &&
                MatchesFilter(state.Filter1, "All Statuses", row.Status) &&
                MatchesFilter(state.Filter2, "All Opcodes", row.Opcode));

        filtered = ApplyKernelSort(filtered, state.SortColumn, state.SortDescending);
        var page = Paginate(filtered.ToList(), state, "events", out var totalRows, out var totalPages);

        _currentKernelPageSource = page;
        KernelRows.Clear();
        foreach (var row in page)
        {
            KernelRows.Add(MapKernelRow(row));
        }

        ClearCollectionIfNeeded(WssRows);
        ClearCollectionIfNeeded(CommandRows);

        UpdateFooter(totalRows, totalPages, state.PageIndex, "events");
    }

    private static List<T> Paginate<T>(IReadOnlyList<T> source, TabQueryState state, string _entity, out int totalRows, out int totalPages)
    {
        totalRows = source.Count;
        totalPages = Math.Max(1, (int)Math.Ceiling(totalRows / (double)PageSize));
        if (state.PageIndex >= totalPages)
        {
            state.PageIndex = totalPages - 1;
        }

        var skip = state.PageIndex * PageSize;
        return source.Skip(skip).Take(PageSize).ToList();
    }

    private void UpdateFooter(int totalRows, int totalPages, int pageIndex, string entity)
    {
        TableFooter = $"{totalRows} {entity} · page {pageIndex + 1} of {totalPages}";
        PagePill = (pageIndex + 1).ToString();
        CanPrevPage = pageIndex > 0;
        CanNextPage = pageIndex + 1 < totalPages;
    }

    private static void ClearCollectionIfNeeded<T>(ObservableCollection<T> collection)
    {
        if (collection.Count > 0)
        {
            collection.Clear();
        }
    }

    private static bool MatchesSearch(string query, params string?[] fields)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return true;
        }

        return fields.Any(x => !string.IsNullOrWhiteSpace(x) && x.Contains(query, StringComparison.OrdinalIgnoreCase));
    }

    private static bool MatchesFilter(string selected, string allLabel, string? value)
    {
        if (string.IsNullOrWhiteSpace(selected) || string.Equals(selected, allLabel, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return string.Equals(selected, value, StringComparison.OrdinalIgnoreCase);
    }

    private static IEnumerable<WssMessageLogRow> ApplyWssSort(IEnumerable<WssMessageLogRow> source, string column, bool desc)
    {
        return (column.ToLowerInvariant(), desc) switch
        {
            ("type", true) => source.OrderByDescending(x => x.Type),
            ("type", false) => source.OrderBy(x => x.Type),
            ("from", true) => source.OrderByDescending(x => x.From),
            ("from", false) => source.OrderBy(x => x.From),
            ("message_id", true) => source.OrderByDescending(x => x.MessageId),
            ("message_id", false) => source.OrderBy(x => x.MessageId),
            ("timestamp", true) => source.OrderByDescending(x => x.Timestamp),
            ("timestamp", false) => source.OrderBy(x => x.Timestamp),
            ("body_summary", true) => source.OrderByDescending(x => x.BodySummary),
            ("body_summary", false) => source.OrderBy(x => x.BodySummary),
            ("sig", true) => source.OrderByDescending(x => x.SigState),
            ("sig", false) => source.OrderBy(x => x.SigState),
            ("seq", false) => source.OrderBy(x => x.Sequence),
            _ => source.OrderByDescending(x => x.Sequence)
        };
    }

    private static IEnumerable<CommandHistoryRow> ApplyCommandSort(IEnumerable<CommandHistoryRow> source, string column, bool desc)
    {
        return (column.ToLowerInvariant(), desc) switch
        {
            ("command_id", true) => source.OrderByDescending(x => x.CommandId),
            ("command_id", false) => source.OrderBy(x => x.CommandId),
            ("method", true) => source.OrderByDescending(x => x.Method),
            ("method", false) => source.OrderBy(x => x.Method),
            ("priority", true) => source.OrderByDescending(x => x.Priority),
            ("priority", false) => source.OrderBy(x => x.Priority),
            ("state", true) => source.OrderByDescending(x => x.State),
            ("state", false) => source.OrderBy(x => x.State),
            ("exec_path", true) => source.OrderByDescending(x => x.ExecPath),
            ("exec_path", false) => source.OrderBy(x => x.ExecPath),
            ("kernel_exec_id", true) => source.OrderByDescending(x => x.KernelExecId),
            ("kernel_exec_id", false) => source.OrderBy(x => x.KernelExecId),
            ("duration", true) => source.OrderByDescending(x => x.DurationMs),
            ("duration", false) => source.OrderBy(x => x.DurationMs),
            ("origin_user", true) => source.OrderByDescending(x => x.OriginUser),
            ("origin_user", false) => source.OrderBy(x => x.OriginUser),
            ("issued_at", false) => source.OrderBy(x => x.IssuedAt),
            _ => source.OrderByDescending(x => x.IssuedAt)
        };
    }

    private static IEnumerable<KernelEventRow> ApplyKernelSort(IEnumerable<KernelEventRow> source, string column, bool desc)
    {
        return (column.ToLowerInvariant(), desc) switch
        {
            ("event_type", true) => source.OrderByDescending(x => x.EventType),
            ("event_type", false) => source.OrderBy(x => x.EventType),
            ("opcode", true) => source.OrderByDescending(x => x.Opcode),
            ("opcode", false) => source.OrderBy(x => x.Opcode),
            ("status", true) => source.OrderByDescending(x => x.Status),
            ("status", false) => source.OrderBy(x => x.Status),
            ("error_code", true) => source.OrderByDescending(x => x.ErrorCode),
            ("error_code", false) => source.OrderBy(x => x.ErrorCode),
            ("kernel_exec_id", true) => source.OrderByDescending(x => x.KernelExecId),
            ("kernel_exec_id", false) => source.OrderBy(x => x.KernelExecId),
            ("agent_seq", true) => source.OrderByDescending(x => x.AgentSeq),
            ("agent_seq", false) => source.OrderBy(x => x.AgentSeq),
            ("command_id", true) => source.OrderByDescending(x => x.CommandId),
            ("command_id", false) => source.OrderBy(x => x.CommandId),
            ("timestamp", false) => source.OrderBy(x => x.Timestamp),
            ("event_id", false) => source.OrderBy(x => x.EventId),
            ("event_id", true) => source.OrderByDescending(x => x.EventId),
            _ => source.OrderByDescending(x => x.EventId)
        };
    }

    private static WssMessageLogRowView MapWssRow(WssMessageLogRow row)
    {
        var type = Placeholder(row.Type);
        var sig = Placeholder(row.SigState);
        return new WssMessageLogRowView(
            Seq: row.Sequence?.ToString() ?? "-",
            Type: type,
            TypeTone: type switch
            {
                "HEARTBEAT" => "Success",
                "TELEMETRY" => "Info",
                "KERNEL_EVENT" => "Info",
                "COMMAND_RESULT" => "Success",
                "COMMAND_DELIVERY" => "Warning",
                "COMMAND_ACK" => "Neutral",
                _ => "Neutral"
            },
            From: Placeholder(row.From),
            FromTone: string.Equals(row.From, "controller", StringComparison.OrdinalIgnoreCase) ? "Warning" : "Info",
            MessageId: Placeholder(row.MessageId),
            Timestamp: FormatLocalTimestamp(row.Timestamp),
            BodySummary: Placeholder(row.BodySummary),
            SigLabel: sig,
            SigTone: string.Equals(sig, "ok", StringComparison.OrdinalIgnoreCase) ? "Success" : "Danger",
            RawJson: row.RawJson ?? "{}");
    }

    private static CommandHistoryRowView MapCommandRow(CommandHistoryRow row)
    {
        var state = Placeholder(row.State);
        var priority = Placeholder(row.Priority);
        return new CommandHistoryRowView(
            CommandId: Placeholder(row.CommandId),
            Method: Placeholder(row.Method),
            MethodTone: "Info",
            Priority: priority,
            PriorityTone: priority.Equals("high", StringComparison.OrdinalIgnoreCase) ? "Warning" : "Neutral",
            State: state,
            StateTone: state switch
            {
                "completed" => "Success",
                "failed" => "Danger",
                "rejected" => "Danger",
                "timed_out" => "Warning",
                "running" => "Info",
                "dispatched" => "Info",
                _ => "Neutral"
            },
            ExecPath: Placeholder(row.ExecPath),
            KernelExecId: Placeholder(row.KernelExecId),
            IssuedAt: FormatLocalTimestamp(row.IssuedAt),
            Duration: row.DurationMs.HasValue ? $"{row.DurationMs.Value}ms" : "-",
            OriginUser: Placeholder(row.OriginUser),
            RawJson: row.RawJson ?? "{}");
    }

    private static KernelEventRowView MapKernelRow(KernelEventRow row)
    {
        var opcode = Placeholder(row.Opcode);
        var status = Placeholder(row.Status);
        return new KernelEventRowView(
            EventId: row.EventId?.ToString() ?? "-",
            EventType: row.EventType?.ToString() ?? "-",
            Opcode: opcode,
            OpcodeTone: opcode switch
            {
                "PING" => "Info",
                "REBOOT" => "Warning",
                "SHUTDOWN" => "Danger",
                _ => "Neutral"
            },
            Status: status,
            StatusTone: status switch
            {
                "ok" => "Success",
                "not_supported" => "Warning",
                "failed" => "Danger",
                _ => "Neutral"
            },
            ErrorCode: row.ErrorCode?.ToString() ?? "-",
            KernelExecId: Placeholder(row.KernelExecId),
            AgentSeq: row.AgentSeq?.ToString() ?? "-",
            CommandId: Placeholder(row.CommandId),
            Timestamp: FormatLocalTimestamp(row.Timestamp),
            RawJson: row.RawJson ?? "{}");
    }

    private static string Placeholder(string? value) => string.IsNullOrWhiteSpace(value) ? "-" : value;

    private static string FormatLocalTimestamp(DateTimeOffset? value)
    {
        if (!value.HasValue)
        {
            return "-";
        }

        return value.Value.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss");
    }

    private void SetRawMessage(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            RawMessageJson = string.Empty;
            HasRawSelection = false;
            RawSizeText = "0 chars · 0 bytes";
            return;
        }

        RawMessageJson = json;
        HasRawSelection = true;
        var bytes = Encoding.UTF8.GetByteCount(json);
        RawSizeText = $"{json.Length} chars · {bytes} bytes";
    }

    public void Dispose()
    {
        _store.SnapshotChanged -= HandleSnapshotChanged;
    }
}
