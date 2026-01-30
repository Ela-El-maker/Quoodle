@extends('admin.layout')

@section('title', 'Compliance')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Compliance Dashboard</h2>
            <p class="text-muted mb-0">Policy versions, attestation failures, and quarantine triggers.</p>
        </div>
        <a class="btn btn-outline-info" href="{{ route('admin.compliance.export') }}">Export Report</a>
    </div>

    <div class="row g-4">
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Policy Profiles</h5>
                </div>
                <div class="panel-body">
                    @forelse($profiles as $profile)
                        <div class="mb-4">
                            <div class="fw-semibold">{{ $profile->profile_id }}</div>
                            <div class="text-muted small">{{ $profile->description }}</div>
                            <div class="text-muted small">Rules: {{ is_array($profile->rules) ? count($profile->rules) : 0 }}</div>
                        </div>
                    @empty
                        <div class="text-muted">No policy profiles found.</div>
                    @endforelse
                </div>
            </div>
        </div>
        <div class="col-lg-6">
            <div class="panel">
                <div class="panel-header">
                    <h5 class="mb-0">Non-compliant Devices</h5>
                </div>
                <div class="panel-body table-responsive">
                    <table class="table table-dark table-hover align-middle">
                        <thead>
                            <tr>
                                <th>Device</th>
                                <th>Status</th>
                                <th>Last Seen</th>
                            </tr>
                        </thead>
                        <tbody>
                            @forelse($nonCompliantDevices as $device)
                                <tr>
                                    <td>{{ $device->device_name ?? $device->device_id }}</td>
                                    <td>
                                        <span class="badge-pill badge-warning">{{ $device->compliance_status }}</span>
                                    </td>
                                    <td>{{ optional($device->last_seen)->diffForHumans() ?? '—' }}</td>
                                </tr>
                            @empty
                                <tr>
                                    <td colspan="3" class="text-muted text-center">No non-compliant devices</td>
                                </tr>
                            @endforelse
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
@endsection
