@extends('admin.layout')

@section('title', 'Audit Log')

@section('content')
<div class="d-flex justify-content-between align-items-center mb-4">
    <h2>Audit Log</h2>
    <div>
        <input type="text" class="form-control d-inline-block w-auto" placeholder="Search...">
        <button class="btn btn-outline-secondary">Filter</button>
    </div>
</div>

<div class="card">
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-striped">
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>User</th>
                        <th>Action</th>
                        <th>Resource</th>
                        <th>Details</th>
                        <th>IP</th>
                    </tr>
                </thead>
                <tbody>
                    @forelse($auditLogs as $log)
                    <tr>
                        <td>{{ $log['timestamp'] }}</td>
                        <td>{{ $log['user'] }}</td>
                        <td>{{ $log['action'] }}</td>
                        <td>{{ $log['resource'] }}</td>
                        <td>{{ $log['details'] }}</td>
                        <td>{{ $log['ip'] }}</td>
                    </tr>
                    @empty
                    <tr>
                        <td colspan="6" class="text-center text-muted">No audit logs available</td>
                    </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>
</div>
@endsection
