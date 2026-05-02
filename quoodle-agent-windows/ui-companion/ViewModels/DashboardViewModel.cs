using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using System.Security.Cryptography;
using System.Text;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public enum TelemetryChartMode
{
    CpuRam,
    Network
}

public enum DashboardFeedType
{
    Heartbeat,
    Telemetry,
    KernelEvent,
    CommandResult,
    CommandDelivery
}

public sealed record DashboardMetricCardModel(
    string Title,
    string Value,
    string Subtitle,
    string Tone,
    string Glyph,
    string DeltaText = "",
    string DeltaTone = "Success",
    string BadgeText = "",
    string BadgeTone = "Neutral",
    string StatusText = "",
    string StatusTone = "Neutral",
    double ValueFontSize = 28);

public sealed record TelemetrySeriesPoint(
    DateTimeOffset Timestamp,
    int Cpu,
    int Ram,
    double NetTx,
    double NetRx);

public sealed record CommandExecutionBin(
    DateTimeOffset Hour,
    int Completed,
    int Failed);

public sealed record LastCommandSummary(
    string Command,
    string CommandId,
    string Priority,
    string StatusLabel,
    string StatusTone,
    string StartedAt,
    string CompletedAt,
    string DurationText,
    string ResultLine,
    string TransportLabel,
    string TransportWorker);

public sealed record DashboardFeedItem(
    DashboardFeedType Type,
    int Sequence,
    DateTimeOffset Timestamp,
    string Summary,
    string Signature,
    string Tone,
    string DotTone,
    string Glyph,
    bool Highlight = false);

internal sealed record RollingTelemetrySample(
    DateTimeOffset Timestamp,
    int Cpu,
    int Ram,
    int Disk,
    double NetTx,
    double NetRx,
    bool IsConnected,
    bool IsHeartbeatObserved);

public sealed class DashboardViewModel : ObservableObject, IDisposable
{
    private readonly AgentStateStore _store;
    private readonly List<RollingTelemetrySample> _samples = new();

    private AgentStateSnapshot _lastSnapshot = AgentStateSnapshot.CreateInitial();
    private TelemetryChartMode _telemetryMode = TelemetryChartMode.Network;

    private string _connectionLabel = "Connecting";
    private string _connectionTone = "Info";
    private string _sessionId = "sess-pending";
    private string _deviceLabel = "pending";
    private string _heartbeatAge = "0s ago";
    private string _agentVersion = "0.0.0";
    private string _osBuild = "0.0.0";
    private string _hwidHash = "sha256:pending";
    private string _policyHash = "sha256:pending";
    private string _wssEndpoint = RuntimeDefaults.DefaultAgentEndpoint;
    private string _reconnectAttempts = "0";

    private DashboardMetricCardModel _wssUptimeCard = new("WSS Uptime (24H)", "--", string.Empty, "Success", "\uE701", ValueFontSize: 56);
    private DashboardMetricCardModel _lastHeartbeatCard = new("Last Heartbeat", "--", string.Empty, "Success", "\uE7BA", ValueFontSize: 46);
    private DashboardMetricCardModel _failedCommandsCard = new("Failed Commands (24H)", "--", string.Empty, "Danger", "\uEA39", ValueFontSize: 52);
    private DashboardMetricCardModel _commandsCompletedCard = new("Commands Completed", "--", string.Empty, "Neutral", "\uE73E");
    private DashboardMetricCardModel _kernelEventsCard = new("Kernel Events (24H)", "--", string.Empty, "Info", "\uE943");
    private DashboardMetricCardModel _cpuUsageCard = new("CPU Usage", "--", string.Empty, "Neutral", "\uE7F4");
    private DashboardMetricCardModel _ramUsageCard = new("RAM Usage", "--", string.Empty, "Neutral", "\uE950");
    private DashboardMetricCardModel _diskUsageCard = new("Disk Usage", "--", string.Empty, "Neutral", "\uEDA2");
    private DashboardMetricCardModel _netTxCard = new("Net TX", "--", string.Empty, "Neutral", "\uE898");
    private DashboardMetricCardModel _netRxCard = new("Net RX", "--", string.Empty, "Neutral", "\uE896");
    private DashboardMetricCardModel _telemetrySnapshotsCard = new("Telemetry Snapshots", "--", string.Empty, "Neutral", "\uE823");

    private IReadOnlyList<TelemetrySeriesPoint> _telemetrySeries = Array.Empty<TelemetrySeriesPoint>();
    private IReadOnlyList<CommandExecutionBin> _commandBins = Array.Empty<CommandExecutionBin>();
    private IReadOnlyList<DashboardFeedItem> _wssFeedItems = Array.Empty<DashboardFeedItem>();
    private LastCommandSummary _lastCommand = new(
        "waiting_for_command",
        "CMD-0000",
        "normal",
        "Pending",
        "Neutral",
        "--",
        "--",
        "--",
        "result.status = pending",
        "_.named_pipe",
        "worker-0");

    public DashboardViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += HandleSnapshotChanged;

        ShowCpuRamCommand = new RelayCommand(() => SetTelemetryMode(TelemetryChartMode.CpuRam));
        ShowNetworkCommand = new RelayCommand(() => SetTelemetryMode(TelemetryChartMode.Network));
        SyncNowCommand = new RelayCommand(() => _store.TriggerSyncNow());

        Apply(store.Snapshot);
    }

    public RelayCommand ShowCpuRamCommand { get; }

    public RelayCommand ShowNetworkCommand { get; }

    public RelayCommand SyncNowCommand { get; }

    public TelemetryChartMode TelemetryMode
    {
        get => _telemetryMode;
        private set => SetProperty(ref _telemetryMode, value);
    }

    public string ConnectionLabel
    {
        get => _connectionLabel;
        private set => SetProperty(ref _connectionLabel, value);
    }

    public string ConnectionTone
    {
        get => _connectionTone;
        private set => SetProperty(ref _connectionTone, value);
    }

    public string SessionId
    {
        get => _sessionId;
        private set => SetProperty(ref _sessionId, value);
    }

    public string DeviceLabel
    {
        get => _deviceLabel;
        private set => SetProperty(ref _deviceLabel, value);
    }

    public string HeartbeatAge
    {
        get => _heartbeatAge;
        private set => SetProperty(ref _heartbeatAge, value);
    }

    public string AgentVersion
    {
        get => _agentVersion;
        private set => SetProperty(ref _agentVersion, value);
    }

    public string OsBuild
    {
        get => _osBuild;
        private set => SetProperty(ref _osBuild, value);
    }

    public string HwidHash
    {
        get => _hwidHash;
        private set => SetProperty(ref _hwidHash, value);
    }

    public string PolicyHash
    {
        get => _policyHash;
        private set => SetProperty(ref _policyHash, value);
    }

    public string WssEndpoint
    {
        get => _wssEndpoint;
        private set => SetProperty(ref _wssEndpoint, value);
    }

    public string ReconnectAttempts
    {
        get => _reconnectAttempts;
        private set => SetProperty(ref _reconnectAttempts, value);
    }

    public DashboardMetricCardModel WssUptimeCard
    {
        get => _wssUptimeCard;
        private set => SetProperty(ref _wssUptimeCard, value);
    }

    public DashboardMetricCardModel LastHeartbeatCard
    {
        get => _lastHeartbeatCard;
        private set => SetProperty(ref _lastHeartbeatCard, value);
    }

    public DashboardMetricCardModel FailedCommandsCard
    {
        get => _failedCommandsCard;
        private set => SetProperty(ref _failedCommandsCard, value);
    }

    public DashboardMetricCardModel CommandsCompletedCard
    {
        get => _commandsCompletedCard;
        private set => SetProperty(ref _commandsCompletedCard, value);
    }

    public DashboardMetricCardModel KernelEventsCard
    {
        get => _kernelEventsCard;
        private set => SetProperty(ref _kernelEventsCard, value);
    }

    public DashboardMetricCardModel CpuUsageCard
    {
        get => _cpuUsageCard;
        private set => SetProperty(ref _cpuUsageCard, value);
    }

    public DashboardMetricCardModel RamUsageCard
    {
        get => _ramUsageCard;
        private set => SetProperty(ref _ramUsageCard, value);
    }

    public DashboardMetricCardModel DiskUsageCard
    {
        get => _diskUsageCard;
        private set => SetProperty(ref _diskUsageCard, value);
    }

    public DashboardMetricCardModel NetTxCard
    {
        get => _netTxCard;
        private set => SetProperty(ref _netTxCard, value);
    }

    public DashboardMetricCardModel NetRxCard
    {
        get => _netRxCard;
        private set => SetProperty(ref _netRxCard, value);
    }

    public DashboardMetricCardModel TelemetrySnapshotsCard
    {
        get => _telemetrySnapshotsCard;
        private set => SetProperty(ref _telemetrySnapshotsCard, value);
    }

    public IReadOnlyList<TelemetrySeriesPoint> TelemetrySeries
    {
        get => _telemetrySeries;
        private set => SetProperty(ref _telemetrySeries, value);
    }

    public IReadOnlyList<CommandExecutionBin> CommandBins
    {
        get => _commandBins;
        private set => SetProperty(ref _commandBins, value);
    }

    public IReadOnlyList<DashboardFeedItem> WssFeedItems
    {
        get => _wssFeedItems;
        private set => SetProperty(ref _wssFeedItems, value);
    }

    public LastCommandSummary LastCommand
    {
        get => _lastCommand;
        private set => SetProperty(ref _lastCommand, value);
    }

    public bool IsCpuRamMode => TelemetryMode == TelemetryChartMode.CpuRam;

    public bool IsNetworkMode => TelemetryMode == TelemetryChartMode.Network;

    public void SetTelemetryMode(TelemetryChartMode mode)
    {
        if (TelemetryMode == mode)
        {
            return;
        }

        TelemetryMode = mode;
        RaisePropertyChanged(nameof(IsCpuRamMode));
        RaisePropertyChanged(nameof(IsNetworkMode));
    }

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        Apply(snapshot);
    }

    private void Apply(AgentStateSnapshot snapshot)
    {
        _lastSnapshot = snapshot;
        var now = DateTimeOffset.UtcNow;

        AppendSample(snapshot, now);
        PruneSamples(now);

        var terminalCommands = snapshot.CommandHistory
            .Where(x => x.Status is CommandExecutionStatus.Succeeded or CommandExecutionStatus.Failed or CommandExecutionStatus.Rejected or CommandExecutionStatus.TimedOut)
            .ToList();

        var commands24h = snapshot.CommandHistory
            .Where(x => x.IssuedAtUtc >= now.AddHours(-24))
            .ToList();

        var failed24h = commands24h.Count(x => x.Status is CommandExecutionStatus.Failed or CommandExecutionStatus.Rejected or CommandExecutionStatus.TimedOut);
        var completed24h = commands24h.Count(x => x.Status == CommandExecutionStatus.Succeeded);
        var active24h = commands24h.Count(x => x.Status is CommandExecutionStatus.Queued or CommandExecutionStatus.Dispatched or CommandExecutionStatus.Executing);
        var kernelEvents24h = CountKernelEvents(snapshot, now);
        var telemetrySnapshots24h = _samples.Count(x => x.Timestamp >= now.AddHours(-24));
        var uptimePercent = ComputeUptimePercent();

        ConnectionLabel = snapshot.Connection.ToString();
        ConnectionTone = ResolveConnectionTone(snapshot.Connection);
        SessionId = BuildSessionId(snapshot);
        DeviceLabel = snapshot.DeviceName;
        HeartbeatAge = FormatAge(snapshot.LastHeartbeatUtc, now);
        AgentVersion = snapshot.AgentVersion;
        OsBuild = Environment.OSVersion.Version.ToString();
        HwidHash = $"sha256:{ShortSha(snapshot.DeviceId + snapshot.DeviceName)}";
        PolicyHash = string.IsNullOrWhiteSpace(snapshot.PolicyHash) ? "sha256:pending" : snapshot.PolicyHash;
        var runtimeEndpoint = string.IsNullOrWhiteSpace(snapshot.Configuration.Transport.Endpoint)
            ? RuntimeDefaults.ResolveAgentEndpoint()
            : snapshot.Configuration.Transport.Endpoint;

        WssEndpoint = runtimeEndpoint;
        ReconnectAttempts = snapshot.ReconnectAttempts.ToString();

        WssUptimeCard = new DashboardMetricCardModel(
            Title: "WSS UPTIME (24H)",
            Value: $"{uptimePercent:0.0}%",
            Subtitle: $"{runtimeEndpoint} · {snapshot.ReconnectAttempts} reconnects",
            Tone: "Success",
            Glyph: "\uE701",
            DeltaText: $"\u2191 {ComputeTrendPercent(sample => sample.IsConnected ? 100 : 0):0.0}%",
            DeltaTone: "Success",
            ValueFontSize: 56);

        LastHeartbeatCard = new DashboardMetricCardModel(
            Title: "LAST HEARTBEAT",
            Value: HeartbeatAge.Replace(" ago", string.Empty),
            Subtitle: "Next expected in ~12s",
            Tone: snapshot.Connection == ConnectionState.Connected ? "Success" : "Warning",
            Glyph: "\uE7BA",
            StatusText: snapshot.Connection == ConnectionState.Connected ? "alive" : "delayed",
            StatusTone: snapshot.Connection == ConnectionState.Connected ? "Success" : "Warning",
            ValueFontSize: 46);

        FailedCommandsCard = new DashboardMetricCardModel(
            Title: "FAILED COMMANDS (24H)",
            Value: failed24h.ToString(),
            Subtitle: BuildFailedSubtitle(commands24h),
            Tone: failed24h > 0 ? "Danger" : "Neutral",
            Glyph: "\uEA39",
            DeltaText: failed24h > 0 ? $"\u2191 {failed24h}" : string.Empty,
            DeltaTone: failed24h > 0 ? "Success" : "Neutral",
            BadgeText: failed24h > 0 ? $"\u2191 {failed24h}" : string.Empty,
            BadgeTone: failed24h > 0 ? "Danger" : "Neutral",
            ValueFontSize: 52);

        CommandsCompletedCard = new DashboardMetricCardModel(
            Title: "COMMANDS COMPLETED",
            Value: completed24h.ToString(),
            Subtitle: "24h window",
            Tone: "Neutral",
            Glyph: "\uE73E",
            DeltaText: completed24h > 0 ? $"\u2191 {Math.Max(1, completed24h / 4)}" : string.Empty,
            DeltaTone: "Success");

        KernelEventsCard = new DashboardMetricCardModel(
            Title: "KERNEL EVENTS (24H)",
            Value: kernelEvents24h.ToString(),
            Subtitle: BuildKernelSubtitle(snapshot),
            Tone: "Info",
            Glyph: "\uE943",
            DeltaText: kernelEvents24h > 0 ? $"\u2191 {Math.Max(1, kernelEvents24h / 3)}" : string.Empty,
            DeltaTone: "Success");

        CpuUsageCard = new DashboardMetricCardModel(
            Title: "CPU USAGE",
            Value: $"{snapshot.CpuPercent}%",
            Subtitle: "PDH counter · sampled 60s",
            Tone: "Neutral",
            Glyph: "\uE7F4");

        RamUsageCard = new DashboardMetricCardModel(
            Title: "RAM USAGE",
            Value: $"{snapshot.MemoryPercent}%",
            Subtitle: "GlobalMemoryStatusEx",
            Tone: "Neutral",
            Glyph: "\uE950");

        DiskUsageCard = new DashboardMetricCardModel(
            Title: "DISK USAGE",
            Value: $"{snapshot.DiskPercent}%",
            Subtitle: "GetDiskFreeSpaceEx",
            Tone: snapshot.DiskPercent >= 85 ? "Warning" : "Neutral",
            Glyph: "\uEDA2");

        NetTxCard = new DashboardMetricCardModel(
            Title: "NET TX",
            Value: $"{snapshot.NetworkTxMbps:0.0} Mbps",
            Subtitle: "GetIfTable2 delta",
            Tone: "Neutral",
            Glyph: "\uE898");

        NetRxCard = new DashboardMetricCardModel(
            Title: "NET RX",
            Value: $"{snapshot.NetworkRxMbps:0.0} Mbps",
            Subtitle: "GetIfTable2 delta",
            Tone: "Neutral",
            Glyph: "\uE896");

        TelemetrySnapshotsCard = new DashboardMetricCardModel(
            Title: "TELEMETRY SNAPSHOTS",
            Value: telemetrySnapshots24h.ToString(),
            Subtitle: "24h · telemetry_basic scope",
            Tone: "Neutral",
            Glyph: "\uE823",
            BadgeText: active24h > 0 ? active24h.ToString() : string.Empty,
            BadgeTone: active24h > 0 ? "Info" : "Neutral");

        TelemetrySeries = BuildTelemetrySeries(now);
        CommandBins = BuildCommandBins(snapshot, now);
        LastCommand = BuildLastCommand(terminalCommands, snapshot);
        WssFeedItems = BuildFeed(snapshot, now);
    }

    private void AppendSample(AgentStateSnapshot snapshot, DateTimeOffset now)
    {
        _samples.Add(new RollingTelemetrySample(
            Timestamp: now,
            Cpu: snapshot.CpuPercent,
            Ram: snapshot.MemoryPercent,
            Disk: snapshot.DiskPercent,
            NetTx: snapshot.NetworkTxMbps,
            NetRx: snapshot.NetworkRxMbps,
            IsConnected: snapshot.Connection == ConnectionState.Connected,
            IsHeartbeatObserved: now - snapshot.LastHeartbeatUtc < TimeSpan.FromSeconds(45)));
    }

    private void PruneSamples(DateTimeOffset now)
    {
        var earliest = now.AddHours(-24);
        _samples.RemoveAll(x => x.Timestamp < earliest);
    }

    private double ComputeUptimePercent()
    {
        if (_samples.Count == 0)
        {
            return _lastSnapshot.Connection == ConnectionState.Connected ? 100.0 : 0.0;
        }

        var connected = _samples.Count(x => x.IsConnected);
        return connected * 100.0 / _samples.Count;
    }

    private double ComputeTrendPercent(Func<RollingTelemetrySample, double> selector)
    {
        if (_samples.Count < 2)
        {
            return 0.0;
        }

        var recent = _samples.TakeLast(Math.Min(8, _samples.Count)).ToList();
        var previous = _samples.TakeLast(Math.Min(16, _samples.Count)).Take(Math.Min(8, Math.Max(0, _samples.Count - recent.Count))).ToList();

        if (previous.Count == 0)
        {
            return 0.0;
        }

        var avgRecent = recent.Average(selector);
        var avgPrev = previous.Average(selector);
        if (Math.Abs(avgPrev) < 0.001)
        {
            return 0.0;
        }

        return ((avgRecent - avgPrev) / Math.Abs(avgPrev)) * 100.0;
    }

    private IReadOnlyList<TelemetrySeriesPoint> BuildTelemetrySeries(DateTimeOffset now)
    {
        var windowStart = now.AddMinutes(-90);
        var source = _samples
            .Where(x => x.Timestamp >= windowStart)
            .OrderBy(x => x.Timestamp)
            .ToList();

        if (source.Count == 0)
        {
            return Array.Empty<TelemetrySeriesPoint>();
        }

        const int maxPoints = 64;
        if (source.Count > maxPoints)
        {
            var step = Math.Max(1, (int)Math.Ceiling(source.Count / (double)maxPoints));
            source = source.Where((_, index) => index % step == 0).ToList();
        }

        return source
            .Select(x => new TelemetrySeriesPoint(x.Timestamp, x.Cpu, x.Ram, x.NetTx, x.NetRx))
            .ToList();
    }

    private static IReadOnlyList<CommandExecutionBin> BuildCommandBins(AgentStateSnapshot snapshot, DateTimeOffset now)
    {
        var localNow = now.ToLocalTime();
        var start = new DateTimeOffset(localNow.Year, localNow.Month, localNow.Day, localNow.Hour, 0, 0, localNow.Offset).AddHours(-10);

        var bins = new List<CommandExecutionBin>(11);
        for (var i = 0; i < 11; i++)
        {
            var hour = start.AddHours(i);
            var next = hour.AddHours(1);

            var slice = snapshot.CommandHistory.Where(x =>
            {
                var ts = x.IssuedAtUtc.ToLocalTime();
                return ts >= hour && ts < next;
            });

            var completed = slice.Count(x => x.Status == CommandExecutionStatus.Succeeded);
            var failed = slice.Count(x => x.Status is CommandExecutionStatus.Failed or CommandExecutionStatus.Rejected or CommandExecutionStatus.TimedOut);

            bins.Add(new CommandExecutionBin(hour, completed, failed));
        }

        return bins;
    }

    private static LastCommandSummary BuildLastCommand(IReadOnlyList<CommandExecutionEntry> terminalCommands, AgentStateSnapshot snapshot)
    {
        var entry = terminalCommands
            .OrderByDescending(x => x.IssuedAtUtc)
            .FirstOrDefault() ?? snapshot.CommandHistory.OrderByDescending(x => x.IssuedAtUtc).FirstOrDefault();

        if (entry is null)
        {
            return new LastCommandSummary(
                Command: "waiting_for_command",
                CommandId: "CMD-0000",
                Priority: "normal",
                StatusLabel: "Pending",
                StatusTone: "Neutral",
                StartedAt: "--",
                CompletedAt: "--",
                DurationText: "--",
                ResultLine: "result.status = pending",
                TransportLabel: "_.named_pipe",
                TransportWorker: "worker-0");
        }

        var started = entry.IssuedAtUtc.ToLocalTime();
        var completed = entry.DurationMs > 0 ? started.AddMilliseconds(entry.DurationMs) : started;
        var statusTone = entry.Status switch
        {
            CommandExecutionStatus.Succeeded => "Success",
            CommandExecutionStatus.Failed => "Danger",
            CommandExecutionStatus.Rejected => "Danger",
            CommandExecutionStatus.TimedOut => "Warning",
            _ => "Neutral"
        };

        var statusLabel = entry.Status switch
        {
            CommandExecutionStatus.Succeeded => "Completed",
            CommandExecutionStatus.Failed => "Failed",
            CommandExecutionStatus.Rejected => "Rejected",
            CommandExecutionStatus.TimedOut => "TimedOut",
            CommandExecutionStatus.Executing => "Running",
            _ => entry.Status.ToString()
        };

        var resultLine = entry.Status == CommandExecutionStatus.Succeeded
            ? "result.status = ok"
            : $"result.status = {entry.Status.ToString().ToLowerInvariant()}";

        return new LastCommandSummary(
            Command: entry.Command.Replace('_', ' '),
            CommandId: entry.Id.ToUpperInvariant(),
            Priority: "normal",
            StatusLabel: statusLabel,
            StatusTone: statusTone,
            StartedAt: started.ToString("HH:mm:ss"),
            CompletedAt: completed.ToString("HH:mm:ss"),
            DurationText: entry.DurationMs > 0 ? $"{entry.DurationMs}ms" : "--",
            ResultLine: resultLine,
            TransportLabel: "_.Named pipe",
            TransportWorker: $"{entry.Source}-47");
    }

    private static IReadOnlyList<DashboardFeedItem> BuildFeed(AgentStateSnapshot snapshot, DateTimeOffset now)
    {
        var feed = new List<DashboardFeedItem>();

        foreach (var activity in snapshot.Activity.Take(24))
        {
            var (type, tone, dotTone, glyph) = InferFromActivity(activity);
            var summary = BuildActivitySummary(activity, type);
            feed.Add(new DashboardFeedItem(
                Type: type,
                Sequence: 0,
                Timestamp: activity.Timestamp,
                Summary: summary,
                Signature: BuildSignature($"{activity.Timestamp.ToUnixTimeMilliseconds()}:{activity.Source}:{summary}"),
                Tone: tone,
                DotTone: dotTone,
                Glyph: glyph));
        }

        foreach (var command in snapshot.CommandHistory.Take(20))
        {
            var isTerminal = command.Status is CommandExecutionStatus.Succeeded or CommandExecutionStatus.Failed or CommandExecutionStatus.Rejected or CommandExecutionStatus.TimedOut;
            var type = isTerminal ? DashboardFeedType.CommandResult : DashboardFeedType.CommandDelivery;
            var tone = isTerminal ? (command.Status == CommandExecutionStatus.Succeeded ? "Success" : "Danger") : "Info";
            var dot = isTerminal ? (command.Status == CommandExecutionStatus.Succeeded ? "Success" : "Danger") : "Neutral";
            var eventTime = command.DurationMs > 0 ? command.IssuedAtUtc.AddMilliseconds(command.DurationMs) : command.IssuedAtUtc;
            var summary = isTerminal
                ? $"{command.Id.ToUpperInvariant()} · {command.Command} · execution_state={command.Status.ToString().ToLowerInvariant()}"
                : $"{command.Id.ToUpperInvariant()} · method={command.Command} · priority=normal · TTL=300s";

            feed.Add(new DashboardFeedItem(
                Type: type,
                Sequence: 0,
                Timestamp: eventTime,
                Summary: summary,
                Signature: BuildSignature($"{command.Id}:{command.IssuedAtUtc.ToUnixTimeMilliseconds()}:{command.Status}"),
                Tone: tone,
                DotTone: dot,
                Glyph: type == DashboardFeedType.CommandResult ? "\uE73E" : "\uE945"));
        }

        var ordered = feed
            .OrderByDescending(x => x.Timestamp)
            .Take(8)
            .ToList();

        var seqTop = Math.Max(ordered.Count, snapshot.Activity.Count + snapshot.CommandHistory.Count) + 58;
        for (var i = 0; i < ordered.Count; i++)
        {
            ordered[i] = ordered[i] with
            {
                Sequence = seqTop - i,
                Highlight = i == 2
            };
        }

        return ordered;
    }

    private static (DashboardFeedType Type, string Tone, string DotTone, string Glyph) InferFromActivity(ActivityEntry activity)
    {
        var blob = $"{activity.Title} {activity.Details} {activity.Source}".ToLowerInvariant();
        if (blob.Contains("heartbeat"))
        {
            return (DashboardFeedType.Heartbeat, "Success", "Success", "\uE7BA");
        }

        if (blob.Contains("telemetry"))
        {
            return (DashboardFeedType.Telemetry, "Info", "Neutral", "\uE9D2");
        }

        if (blob.Contains("kernel"))
        {
            return (DashboardFeedType.KernelEvent, "Info", "Neutral", "\uE943");
        }

        if (blob.Contains("command"))
        {
            var isError = activity.Severity is ActivitySeverity.Warning or ActivitySeverity.Error;
            return (DashboardFeedType.CommandResult, isError ? "Danger" : "Success", isError ? "Danger" : "Success", "\uE73E");
        }

        return (DashboardFeedType.CommandDelivery, "Neutral", "Neutral", "\uE945");
    }

    private static string BuildActivitySummary(ActivityEntry activity, DashboardFeedType type)
    {
        return type switch
        {
            DashboardFeedType.Heartbeat => "status=alive, uptime=13248s, error_state=ok",
            DashboardFeedType.Telemetry => "telemetry_basic · cpu=12% ram=45% disk=60%",
            DashboardFeedType.KernelEvent => "event_id=14 · opcode=PING · status=ok",
            DashboardFeedType.CommandResult => $"cmd={activity.Title.ToLowerInvariant().Replace(' ', '_')} · status={activity.Severity.ToString().ToLowerInvariant()}",
            _ => activity.Details
        };
    }

    private static int CountKernelEvents(AgentStateSnapshot snapshot, DateTimeOffset now)
    {
        var cutoff = now.AddHours(-24);
        var count = snapshot.Activity.Count(x =>
            x.Timestamp >= cutoff &&
            ($"{x.Title} {x.Details} {x.Source}").ToLowerInvariant().Contains("kernel"));

        if (count == 0)
        {
            count = snapshot.CommandHistory.Count(x =>
                x.IssuedAtUtc >= cutoff &&
                x.Command.Contains("events", StringComparison.OrdinalIgnoreCase));
        }

        return count;
    }

    private static string BuildFailedSubtitle(IReadOnlyList<CommandExecutionEntry> commands24h)
    {
        var failed = commands24h
            .Where(x => x.Status is CommandExecutionStatus.Failed or CommandExecutionStatus.Rejected or CommandExecutionStatus.TimedOut)
            .Take(2)
            .Select(x => x.Command)
            .ToList();

        return failed.Count == 0 ? "no failed commands" : string.Join(" \u00d7 1, ", failed) + " \u00d7 1";
    }

    private static string BuildKernelSubtitle(AgentStateSnapshot snapshot)
    {
        var commands = snapshot.CommandHistory
            .Select(x => x.Command.ToUpperInvariant())
            .Distinct()
            .Take(3)
            .ToList();

        if (commands.Count == 0)
        {
            return "No kernel opcode telemetry";
        }

        return string.Join(", ", commands.Select(x => $"{x} \u00d7 1"));
    }

    private static string ResolveConnectionTone(ConnectionState state)
    {
        return state switch
        {
            ConnectionState.Connected => "Success",
            ConnectionState.Reconnecting => "Warning",
            ConnectionState.Offline => "Danger",
            ConnectionState.AuthFailed => "Danger",
            _ => "Info"
        };
    }

    private static string BuildSessionId(AgentStateSnapshot snapshot)
    {
        var seed = $"{snapshot.DeviceId}:{snapshot.AgentVersion}";
        return $"sess-{ShortSha(seed)[..12]}";
    }

    private static string ShortSha(string text)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        return Convert.ToHexString(bytes).ToLowerInvariant()[..12];
    }

    private static string BuildSignature(string seed)
    {
        return $"sig:{ShortSha(seed)[..6]}";
    }

    private static string FormatAge(DateTimeOffset timestamp, DateTimeOffset now)
    {
        var age = now - timestamp;
        if (age.TotalSeconds < 60)
        {
            return $"{Math.Max(1, (int)age.TotalSeconds)}s ago";
        }

        if (age.TotalMinutes < 60)
        {
            return $"{(int)age.TotalMinutes}m ago";
        }

        return $"{(int)age.TotalHours}h ago";
    }

    public void Dispose()
    {
        _store.SnapshotChanged -= HandleSnapshotChanged;
    }
}
