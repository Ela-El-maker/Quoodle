@extends('admin.layout')

@section('title', 'Command Result')

@section('content')
    @php
        $result = is_array($command->result) ? $command->result : [];
        $details = $result['details'] ?? null;
        $redact = function ($value) use (&$redact) {
            if (is_array($value)) {
                $out = [];
                foreach ($value as $k => $v) {
                    if (is_string($k) && $k === 'data_b64') {
                        $out[$k] = '[omitted]';
                        continue;
                    }
                    if (is_string($k) && in_array($k, ['entries', 'processes', 'services', 'mounts', 'routes', 'users', 'sessions'], true)) {
                        $out[$k] = is_array($v) ? ['count' => count($v)] : $v;
                        continue;
                    }
                    $out[$k] = $redact($v);
                }
                return $out;
            }
            return $value;
        };
        $detailsView = $redact($details);
        $resultView = $redact($result);
        $status = $result['status'] ?? $command->state ?? 'unknown';
        $badgeClass = 'badge-muted';
        if (in_array($status, ['ok', 'completed'], true)) {
            $badgeClass = 'badge-success';
        } elseif (in_array($status, ['failed', 'error', 'rejected', 'expired'], true)) {
            $badgeClass = 'badge-danger';
        } elseif (in_array($command->state, ['dispatched', 'ack_received', 'executing'], true)) {
            $badgeClass = 'badge-info';
        } elseif (in_array($command->state, ['queued', 'pending'], true)) {
            $badgeClass = 'badge-warning';
        }
    @endphp

    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Command Result</h2>
            <p class="text-muted mb-0">{{ $command->method }} · {{ $command->device->device_name ?? $command->device_id }}</p>
        </div>
        <div class="d-flex gap-2">
            <a href="{{ route('admin.commands.show', $command) }}" class="btn btn-outline-secondary">Timeline</a>
            <a href="{{ route('admin.commands') }}" class="btn btn-outline-secondary">Back</a>
        </div>
    </div>

    <div class="row g-4">
        <div class="col-lg-8">
            <div class="panel">
                <div class="panel-header d-flex justify-content-between align-items-center">
                    <h5 class="mb-0">Result Summary</h5>
                    <span class="badge-pill {{ $badgeClass }}">{{ strtoupper($status) }}</span>
                </div>
                <div class="panel-body">
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="text-muted small">Command</div>
                            <div class="fw-semibold">{{ $command->id }}</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted small">Completed</div>
                            <div class="fw-semibold">{{ optional($command->completed_at)->toIso8601String() ?? '—' }}</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted small">User</div>
                            <div class="fw-semibold">{{ $command->user->display_name ?? $command->user_id }}</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted small">Device</div>
                            <div class="fw-semibold">{{ $command->device->device_name ?? $command->device_id }}</div>
                        </div>
                        <div class="col-12">
                            <div class="text-muted small">Notes</div>
                            <div class="fw-semibold">{{ $result['notes'] ?? '—' }}</div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="panel mt-4">
                <div class="panel-header">
                    <h5 class="mb-0">Details</h5>
                </div>
                <div class="panel-body">
                    @if(! empty($detailsView) && is_array($detailsView))
                        <div class="table-responsive">
                            <table class="table table-dark table-sm align-middle mb-0">
                                <thead>
                                    <tr>
                                        <th>Key</th>
                                        <th>Value</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    @foreach($detailsView as $key => $value)
                                        <tr>
                                            <td class="text-muted">{{ $key }}</td>
                                            <td class="text-break">{{ is_array($value) ? json_encode($value, JSON_UNESCAPED_SLASHES) : $value }}</td>
                                        </tr>
                                    @endforeach
                                </tbody>
                            </table>
                        </div>
                    @else
                        <div class="text-muted">No detail payload yet.</div>
                    @endif
                </div>
            </div>

            <div class="panel mt-4">
                <div class="panel-header">
                    <h5 class="mb-0">Raw Payload (Redacted)</h5>
                </div>
                <div class="panel-body">
                    @if(! empty($resultView))
                        <pre class="bg-black bg-opacity-25 border border-secondary rounded p-3 mb-0 small">{{ json_encode($resultView, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) }}</pre>
                    @else
                        <div class="text-muted">No result payload yet.</div>
                    @endif
                </div>
            </div>
        </div>

        <div class="col-lg-4">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Artifact</h5>
                </div>
                <div class="panel-body">
                    <div class="mb-3">
                        <div class="text-muted small">Artifact URL</div>
                        <div class="text-break">{{ $result['artifact_url'] ?? '—' }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Checksum</div>
                        <div class="text-break">{{ $result['artifact_checksum'] ?? '—' }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">Path</div>
                        <div class="text-break">{{ is_array($details) ? ($details['path'] ?? $details['relative_path'] ?? '—') : '—' }}</div>
                    </div>
                    <div>
                        <div class="text-muted small">SHA256</div>
                        <div class="text-break">{{ is_array($details) ? ($details['sha256'] ?? '—') : '—' }}</div>
                    </div>
                </div>
            </div>

            <div class="panel mt-4">
                <div class="panel-header">
                    <h5 class="mb-0">Request Metadata</h5>
                </div>
                <div class="panel-body">
                    <div class="mb-3">
                        <div class="text-muted small">Queued</div>
                        <div class="fw-semibold">{{ optional($command->queued_at ?? $command->created_at)->toIso8601String() }}</div>
                    </div>
                    <div class="mb-3">
                        <div class="text-muted small">State</div>
                        <div class="fw-semibold">{{ $command->state ?? '—' }}</div>
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
