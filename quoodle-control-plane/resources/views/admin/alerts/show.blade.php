@extends('admin.layout')

@section('title', 'Alert Detail')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Alert {{ $alert->alert_id ?? $alert->id }}</h2>
            <p class="text-muted mb-0">{{ $alert->category }} · {{ ucfirst($alert->severity) }}</p>
        </div>
        <a href="{{ route('admin.alerts') }}" class="btn btn-outline-secondary">Back to Alerts</a>
    </div>

    <div class="panel">
        <div class="panel-header">
            <h5 class="mb-0">Alert Details</h5>
            <span class="badge-pill {{ $alert->acknowledged ? 'badge-success' : 'badge-warning' }}">
                {{ $alert->acknowledged ? 'Acknowledged' : 'Pending' }}
            </span>
        </div>
        <div class="panel-body">
            <div class="row g-3">
                <div class="col-md-6">
                    <div class="text-muted small">Device</div>
                    <div class="fw-semibold">{{ $alert->device->device_name ?? $alert->device_id }}</div>
                </div>
                <div class="col-md-6">
                    <div class="text-muted small">Timestamp</div>
                    <div class="fw-semibold">{{ optional($alert->timestamp ?? $alert->created_at)->toIso8601String() }}</div>
                </div>
                <div class="col-12">
                    <div class="text-muted small">Message</div>
                    <div class="fw-semibold">{{ $alert->message }}</div>
                </div>
            </div>
        </div>
    </div>
@endsection
