@extends('admin.layout')

@section('title', 'Investigations')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Investigation Workspace</h2>
            <p class="text-muted mb-0">Curate suspicious events, commands, and devices into case bundles.</p>
        </div>
        <button class="btn btn-outline-info">New Case</button>
    </div>

    <div class="row g-4">
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Pinned Audit Events</h5>
                </div>
                <div class="panel-body">
                    @forelse($latestAudit as $entry)
                        <div class="mb-3">
                            <div class="fw-semibold">{{ $entry->event_type }}</div>
                            <div class="text-muted small">{{ $entry->device_id ?? '—' }} · {{ optional($entry->timestamp)->toIso8601String() }}</div>
                            <div class="text-muted small text-truncate">Hash: {{ $entry->hash }}</div>
                        </div>
                    @empty
                        <div class="text-muted">No audit events available.</div>
                    @endforelse
                </div>
            </div>
        </div>
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Recent High-Risk Commands</h5>
                </div>
                <div class="panel-body">
                    @forelse($latestCommands as $command)
                        <div class="mb-3">
                            <div class="fw-semibold">{{ $command->method }}</div>
                            <div class="text-muted small">{{ $command->device->device_name ?? $command->device_id }} · {{ optional($command->created_at)->diffForHumans() }}</div>
                            <div class="text-muted small">User: {{ $command->user->display_name ?? $command->user_id }}</div>
                        </div>
                    @empty
                        <div class="text-muted">No commands available.</div>
                    @endforelse
                </div>
            </div>
        </div>
    </div>

    <div class="panel mt-4">
        <div class="panel-header">
            <h5 class="mb-0">Case Collections</h5>
            <button class="btn btn-sm btn-outline-secondary">Export Bundle</button>
        </div>
        <div class="panel-body">
            <div class="text-muted">No case bundles yet. Create a case to collect evidence and export a signed bundle.</div>
        </div>
    </div>
@endsection
