namespace Quoodle.Agent.UiCompanion.Models;

public sealed record WssMessageLogRow(
    int? Sequence,
    string? Type,
    string? From,
    string? MessageId,
    DateTimeOffset? Timestamp,
    string? BodySummary,
    string? SigState,
    string? RawJson);

public sealed record CommandHistoryRow(
    string? CommandId,
    string? Method,
    string? Priority,
    string? State,
    string? ExecPath,
    string? KernelExecId,
    DateTimeOffset? IssuedAt,
    int? DurationMs,
    string? OriginUser,
    string? RawJson);

public sealed record KernelEventRow(
    int? EventId,
    int? EventType,
    string? Opcode,
    string? Status,
    int? ErrorCode,
    string? KernelExecId,
    int? AgentSeq,
    string? CommandId,
    DateTimeOffset? Timestamp,
    string? RawJson);
