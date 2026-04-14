using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;
using Quoodle.Agent.UiCompanion.ViewModels;
using System.Text.Json;
using Xunit;

namespace Quoodle.Agent.UiCompanion.Tests;

public sealed class ActivityDiagnosticsViewModelTests
{
    [Fact]
    public void WssDefaultsAndPaginationFollowExpectedOrder()
    {
        var now = DateTimeOffset.UtcNow;
        var wssRows = Enumerable.Range(1, 23)
            .Select(i => new WssMessageLogRow(
                Sequence: i,
                Type: i % 2 == 0 ? "HEARTBEAT" : "COMMAND_RESULT",
                From: i % 4 == 0 ? "controller" : "agent",
                MessageId: $"m-{i:000}",
                Timestamp: now.AddSeconds(-i * 45),
                BodySummary: $"summary-{i}",
                SigState: i % 5 == 0 ? "not_ok" : "ok",
                RawJson: $"{{\"seq\":{i}}}"))
            .ToList();

        var provider = new TestProvider(BuildSnapshot(now, wssRows: wssRows));
        using var store = new AgentStateStore(provider);
        using var vm = new ActivityDiagnosticsViewModel(store);

        Assert.Equal(23, vm.WssCount);
        Assert.Equal(10, vm.WssRows.Count);
        Assert.Equal("23", vm.WssRows[0].Seq);
        Assert.Equal("23 messages · page 1 of 3", vm.TableFooter);

        vm.NextPage();
        Assert.Equal("2", vm.PagePill);
        Assert.Equal("13", vm.WssRows[0].Seq);

        vm.NextPage();
        Assert.Equal("3", vm.PagePill);
        Assert.Equal(3, vm.WssRows.Count);
        Assert.False(vm.CanNextPage);
    }

    [Fact]
    public void CommandFiltersAndSortAreAppliedWithoutChangingTabCounts()
    {
        var now = DateTimeOffset.UtcNow;
        var commandRows = new List<CommandHistoryRow>
        {
            new("CMD-001", "lock_screen", "high", "completed", ">. IOCTL", "kexec-001", now.AddMinutes(-1), 9200, "UID001", "{\"id\":\"1\"}"),
            new("CMD-002", "ping", "normal", "failed", "_. Named Pipe", "kexec-002", now.AddMinutes(-2), 700, "UID002", "{\"id\":\"2\"}"),
            new("CMD-003", "collect_system_info", "normal", "failed", ">. IOCTL", "kexec-003", now.AddMinutes(-3), 8400, "UID001", "{\"id\":\"3\"}"),
            new("CMD-004", "list_processes", "normal", "completed", ">. IOCTL", "kexec-004", now.AddMinutes(-4), 620, "UID003", "{\"id\":\"4\"}")
        };

        var provider = new TestProvider(BuildSnapshot(now, commandRows: commandRows));
        using var store = new AgentStateStore(provider);
        using var vm = new ActivityDiagnosticsViewModel(store);

        vm.SelectTab(ActivityDiagnosticsTab.CommandHistory);
        Assert.Equal(4, vm.CommandCount);
        Assert.Equal("CMD-001", vm.CommandRows[0].CommandId);

        vm.SetFilter1("failed");
        Assert.Equal(2, vm.CommandRows.Count);
        Assert.All(vm.CommandRows, row => Assert.Equal("failed", row.State));
        Assert.Equal(4, vm.CommandCount);

        vm.ToggleSort("duration");
        Assert.Equal("8400ms", vm.CommandRows[0].Duration);
        vm.ToggleSort("duration");
        Assert.Equal("700ms", vm.CommandRows[0].Duration);
    }

    [Fact]
    public void KernelRowsSupportMissingFieldsAndExportCurrentViewMetadata()
    {
        var now = DateTimeOffset.UtcNow;
        var kernelRows = new List<KernelEventRow>
        {
            new(14, 1, "PING", "ok", 0, "kexec-014", 114, "CMD-0045", now.AddMinutes(-1), "{\"event\":14}"),
            new(null, 2, null, null, null, null, null, null, null, "{\"event\":\"missing\"}")
        };

        var provider = new TestProvider(BuildSnapshot(now, kernelRows: kernelRows));
        using var store = new AgentStateStore(provider);
        using var vm = new ActivityDiagnosticsViewModel(store);

        vm.SelectTab(ActivityDiagnosticsTab.KernelEvents);
        Assert.Contains(vm.KernelRows, row => row.EventId == "-");
        Assert.Contains(vm.KernelRows, row => row.Opcode == "-");

        var selected = vm.KernelRows.First();
        vm.SelectKernelRow(selected);
        Assert.True(vm.HasRawSelection);
        Assert.Contains("bytes", vm.RawSizeText);

        var exportJson = vm.BuildCurrentViewExportJson();
        using var doc = JsonDocument.Parse(exportJson);
        Assert.Equal("KernelEvents", doc.RootElement.GetProperty("tab").GetString());

        var rows = doc.RootElement.GetProperty("rows");
        Assert.Equal(vm.KernelRows.Count, rows.GetArrayLength());
        Assert.Equal(10, doc.RootElement.GetProperty("paging").GetProperty("page_size").GetInt32());
    }

    private static AgentStateSnapshot BuildSnapshot(
        DateTimeOffset now,
        IReadOnlyList<WssMessageLogRow>? wssRows = null,
        IReadOnlyList<CommandHistoryRow>? commandRows = null,
        IReadOnlyList<KernelEventRow>? kernelRows = null)
    {
        return AgentStateSnapshot.CreateInitial() with
        {
            IsPaired = true,
            DeviceId = "PC001",
            DeviceName = "WORKSTATION-PC001",
            AgentVersion = "0.0.1",
            PolicyHash = "sha256:policy123",
            Connection = ConnectionState.Connected,
            LastSyncUtc = now,
            LastHeartbeatUtc = now.AddSeconds(-20),
            WssMessageLog = wssRows ?? Array.Empty<WssMessageLogRow>(),
            CommandHistoryLog = commandRows ?? Array.Empty<CommandHistoryRow>(),
            KernelEvents = kernelRows ?? Array.Empty<KernelEventRow>(),
            Activity = Array.Empty<ActivityEntry>(),
            CommandHistory = Array.Empty<CommandExecutionEntry>()
        };
    }
}
