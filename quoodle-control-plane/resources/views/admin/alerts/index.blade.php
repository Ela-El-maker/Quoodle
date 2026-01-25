@extends('admin.layout')

@section('title', 'Alerts Management')

@section('content')
<div class="d-flex justify-content-between align-items-center mb-4">
    <h2>Alerts</h2>
    <a href="#" class="btn btn-primary">Create Alert</a>
</div>

<div class="card">
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-striped">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Type</th>
                        <th>Device</th>
                        <th>Message</th>
                        <th>Severity</th>
                        <th>Status</th>
                        <th>Created</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($alerts as $alert)
                    <tr>
                        <td>{{ $alert->id }}</td>
                        <td>{{ $alert->category }}</td>
                        <td>{{ $alert->device->device_name ?? $alert->device_id }}</td>
                        <td>{{ $alert->message }}</td>
                        <td>
                            <span class="badge bg-{{ $alert->severity === 'critical' ? 'danger' : ($alert->severity === 'high' ? 'warning' : ($alert->severity === 'medium' ? 'info' : 'secondary')) }}">
                                {{ ucfirst($alert->severity) }}
                            </span>
                        </td>
                        <td>
                            @if($alert->acknowledged)
                                <span class="badge bg-success">Acknowledged</span>
                            @else
                                <span class="badge bg-warning">Pending</span>
                            @endif
                        </td>
                        <td>{{ $alert->created_at->format('M d, H:i') }}</td>
                        <td>
                            @if(!$alert->acknowledged_at)
                                <a href="#" class="btn btn-sm btn-outline-success">Acknowledge</a>
                            @endif
                            <a href="#" class="btn btn-sm btn-outline-primary">View</a>
                        </td>
                    </tr>
                    @endforeach
                </tbody>
            </table>
        </div>

        {{ $alerts->links() }}
    </div>
</div>
@endsection
