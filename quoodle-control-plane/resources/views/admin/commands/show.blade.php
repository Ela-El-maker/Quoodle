@extends('admin.layout')

@section('title', 'Command Timeline')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Command {{ $command->id }}</h2>
            <p class="text-muted mb-0">{{ $command->method }} · {{ $command->device->device_name ?? $command->device_id }}</p>
        </div>
        <a href="{{ route('admin.commands') }}" class="btn btn-outline-secondary">Back to Commands</a>
    </div>

    <div class="row g-4">
        <div class="col-lg-7">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Lifecycle Timeline</h5>
                </div>
                <div class="panel-body">
                    <div class="d-flex flex-column gap-3">
                        @foreach($timeline as $step)
                            <div class="d-flex align-items-start gap-3">
                                <span class="badge-pill {{ $step['status'] === 'complete' ? 'badge-success' : ($step['status'] === 'failed' ? 'badge-danger' : ($step['status'] === 'active' ? 'badge-info' : 'badge-muted')) }}">
                                    {{ strtoupper($step['status']) }}
                                </span>
                                <div>
                                    <div class="fw-semibold">{{ $step['label'] }}</div>
                                    <div class="text-muted small">{{ $step['timestamp'] ?? 'Pending' }}</div>
                                </div>
                            </div>
                        @endforeach
                    </div>
                </div>
            </div>

            <div class="panel mt-4">
                <div class="panel-header">
                    <h5 class="mb-0">Signed Results</h5>
                </div>
                <div class="panel-body">
                    <div class="mb-3">
                        <div class="text-muted small">Result status</div>
                        <div class="fw-semibold">{{ $command->result['status'] ?? $command->state ?? 'unknown' }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Notes</div>
                        <div class="fw-semibold">{{ $command->result['notes'] ?? '—' }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Artifact URL</div>
                        <div class="text-break">{{ $command->result['artifact_url'] ?? '—' }}</div>
                    </div>
                    <div>
                        <div class="text-muted small">Checksum</div>
                        <div class="text-break">{{ $command->result['artifact_checksum'] ?? '—' }}</div>
                    </div>
                </div>
            </div>
        </div>

        <div class="col-lg-5">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Command Metadata</h5>
                </div>
                <div class="panel-body">
                    <div class="mb-3">
                        <div class="text-muted small">Device</div>
                        <div class="fw-semibold">{{ $command->device->device_name ?? $command->device_id }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">User</div>
                        <div class="fw-semibold">{{ $command->user->display_name ?? $command->user_id }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Queued</div>
                        <div class="fw-semibold">{{ optional($command->queued_at ?? $command->created_at)->toIso8601String() }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Completed</div>
                        <div class="fw-semibold">{{ optional($command->completed_at)->toIso8601String() ?? '—' }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Request Signature</div>
                        <div class="text-break">{{ $command->request_sig ?? '—' }}</div>
                    </div>
                    <div>
                        <div class="text-muted small">Envelope Signature</div>
                        <div class="text-break">{{ $command->envelope_sig ?? '—' }}</div>
                    </div>
                </div>
            </div>
        </div>
    </div>
@endsection
