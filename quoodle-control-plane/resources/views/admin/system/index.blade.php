@extends('admin.layout')

@section('title', 'System Status')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">System Status</h2>
            <p class="text-muted mb-0">Control plane health, gateway throughput, and queue depth.</p>
        </div>
        <button class="btn btn-outline-secondary">Refresh</button>
    </div>

    <div class="row g-4">
        <div class="col-lg-4">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Control Plane</div>
                <div class="fw-semibold">Operational</div>
                <div class="text-muted small">Devices online: {{ $metrics['devices_online'] ?? 0 }}/{{ $metrics['devices_total'] ?? 0 }}</div>
            </div>
        </div>
        <div class="col-lg-4">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Gateway</div>
                <div class="fw-semibold">Healthy</div>
                <div class="text-muted small">Queue depth: {{ $metrics['commands_pending'] ?? 0 }}</div>
            </div>
        </div>
        <div class="col-lg-4">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Audit Ledger</div>
                <div class="fw-semibold">{{ ($metrics['alerts_unack'] ?? 0) > 0 ? 'Attention' : 'Clear' }}</div>
                <div class="text-muted small">Unacknowledged alerts: {{ $metrics['alerts_unack'] ?? 0 }}</div>
            </div>
        </div>
    </div>

    <div class="row g-4 mt-1">
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Services</h5>
                </div>
                <div class="panel-body">
                    <div class="d-flex justify-content-between mb-3">
                        <span>Redis</span>
                        <span class="badge-pill {{ ($health['redis']['status'] ?? '') === 'healthy' ? 'badge-success' : 'badge-danger' }}">
                            {{ ucfirst($health['redis']['status'] ?? 'unknown') }}
                        </span>
                    </div>
                    <div class="d-flex justify-content-between mb-3">
                        <span>Gateway</span>
                        <span class="badge-pill {{ ($health['gateway']['status'] ?? '') === 'healthy' ? 'badge-success' : (($health['gateway']['status'] ?? '') === 'degraded' ? 'badge-warning' : 'badge-danger') }}">
                            {{ ucfirst($health['gateway']['status'] ?? 'unknown') }}
                        </span>
                    </div>
                    <div class="d-flex justify-content-between">
                        <span>Workers</span>
                        <span class="badge-pill {{ ($health['workers']['status'] ?? '') === 'healthy' ? 'badge-success' : 'badge-warning' }}">
                            {{ ucfirst($health['workers']['status'] ?? 'unknown') }}
                        </span>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Queue Health</h5>
                </div>
                <div class="panel-body">
                    <div class="d-flex justify-content-between mb-3">
                        <span>Database</span>
                        <span class="badge-pill {{ ($health['database']['status'] ?? '') === 'healthy' ? 'badge-success' : 'badge-danger' }}">
                            {{ ucfirst($health['database']['status'] ?? 'unknown') }}
                        </span>
                    </div>
                    <div class="d-flex justify-content-between">
                        <span>Alerts pending</span>
                        <span class="fw-semibold">{{ $metrics['alerts_unack'] ?? 0 }}</span>
                    </div>
                </div>
            </div>
        </div>
    </div>
@endsection
