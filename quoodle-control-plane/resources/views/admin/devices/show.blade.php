@extends('admin.layout')

@section('title', 'Device Detail')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">{{ $device->device_name ?? $device->device_id }}</h2>
            <p class="text-muted mb-0">Device ID: {{ $device->device_id }}</p>
        </div>
        <a href="{{ route('admin.devices') }}" class="btn btn-outline-secondary">Back to Fleet</a>
    </div>

    <div class="row g-4">
        <div class="col-lg-4">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Lifecycle</div>
                @php
                    $lifecycle = strtolower($device->lifecycle_state ?? 'unknown');
                    if ($lifecycle === 'active') {
                        $lifecycle = 'online';
                    } elseif ($lifecycle === 'quarantine') {
                        $lifecycle = 'quarantined';
                    }
                @endphp
                <div class="fw-semibold">{{ ucfirst($lifecycle) }}</div>
                <div class="text-muted small">Last seen: {{ optional($device->last_seen)->diffForHumans() ?? '—' }}</div>
            </div>
        </div>
        <div class="col-lg-4">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Compliance</div>
                <div class="fw-semibold">{{ ucfirst($device->compliance_status ?? 'unknown') }}</div>
                <div class="text-muted small">Risk score: {{ $device->risk_score ?? '—' }}</div>
            </div>
        </div>
        <div class="col-lg-4">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Owner</div>
                <div class="fw-semibold">{{ $device->user->display_name ?? 'Unassigned' }}</div>
                <div class="text-muted small">OS: {{ $device->os_build ?? '—' }}</div>
            </div>
        </div>
    </div>

    <div class="row g-4 mt-1">
        <div class="col-lg-12">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Linked Mobile Devices</h5>
                </div>
                <div class="panel-body">
                    @forelse($mobileLinks ?? [] as $link)
                        <div class="mb-3">
                            <div class="fw-semibold">
                                {{ $link->mobileDevice->device_model ?? 'Mobile Device' }}
                                <span class="text-muted small">({{ $link->mobileDevice->platform ?? 'unknown' }})</span>
                            </div>
                            <div class="text-muted small">
                                Fingerprint: {{ $link->mobileDevice->device_fingerprint ?? '—' }}
                            </div>
                            <div class="text-muted small">
                                Last seen: {{ optional($link->mobileDevice->last_seen_at)->diffForHumans() ?? '—' }}
                                • Linked: {{ optional($link->linked_at)->diffForHumans() ?? '—' }}
                            </div>
                        </div>
                    @empty
                        <div class="text-muted">No linked mobile devices.</div>
                    @endforelse
                </div>
            </div>
        </div>
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Recent Commands</h5>
                </div>
                <div class="panel-body">
                    @forelse($recentCommands as $command)
                        <div class="mb-3">
                            <div class="fw-semibold">{{ $command->method }}</div>
                            <div class="text-muted small">{{ optional($command->created_at)->diffForHumans() }}</div>
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
                                $summary = $details ?? ($result['notes'] ?? null);
                                $summaryView = $redact($summary);
                                $summaryText = $summaryView ? json_encode($summaryView, JSON_UNESCAPED_SLASHES) : null;
                            @endphp
                            @if($summaryText)
                                <div class="text-muted small">Result: {{ \Illuminate\Support\Str::limit($summaryText, 120) }}</div>
                            @endif
                            <a class="btn btn-sm btn-outline-info mt-2" href="{{ route('admin.commands.show', $command) }}">View Timeline</a>
                        </div>
                    @empty
                        <div class="text-muted">No recent commands.</div>
                    @endforelse
                </div>
            </div>
        </div>
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Recent Alerts</h5>
                </div>
                <div class="panel-body">
                    @forelse($recentAlerts as $alert)
                        <div class="mb-3">
                            <div class="fw-semibold">{{ $alert->category }}</div>
                            <div class="text-muted small">{{ optional($alert->created_at)->diffForHumans() }}</div>
                            <a class="btn btn-sm btn-outline-info mt-2" href="{{ route('admin.alerts.show', $alert) }}">View Alert</a>
                        </div>
                    @empty
                        <div class="text-muted">No recent alerts.</div>
                    @endforelse
                </div>
            </div>
        </div>
    </div>
@endsection
