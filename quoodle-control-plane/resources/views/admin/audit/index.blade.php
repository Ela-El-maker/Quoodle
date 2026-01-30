@extends('admin.layout')

@section('title', 'Audit Log')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Audit Ledger</h2>
            <p class="text-muted mb-0">Immutable log of every command, pairing, and policy event.</p>
        </div>
        <div class="d-flex flex-wrap gap-2 align-items-center">
            <form method="GET" class="d-flex gap-2">
                <input type="text" name="q" value="{{ $search }}" class="form-control form-control-sm bg-transparent text-white border-secondary" placeholder="Search audit id or device">
                <button class="btn btn-sm btn-outline-secondary" type="submit">Filter</button>
            </form>
            <a class="btn btn-outline-secondary btn-sm" href="{{ route('admin.audit.export') }}">Export CSV</a>
        </div>
    </div>

    <div class="panel">
        <div class="panel-header">
            <h5 class="mb-0">Latest entries</h5>
        </div>
        <div class="panel-body table-responsive">
            <table class="table table-dark table-hover align-middle">
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Audit ID</th>
                        <th>Actor</th>
                        <th>Device</th>
                        <th>Event</th>
                        <th>Hash</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($auditLogs as $log)
                        <tr>
                            <td>{{ optional($log->timestamp)->toIso8601String() ?? '-' }}</td>
                            <td class="text-truncate" style="max-width: 140px;">{{ $log->audit_id }}</td>
                            <td>{{ $log->actor }}</td>
                            <td>{{ $log->device_id ?? '—' }}</td>
                            <td>{{ $log->event_type }}</td>
                            <td class="text-truncate" style="max-width: 180px;">{{ $log->hash }}</td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="6" class="text-center text-muted">No audit entries available</td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
@endsection
