@extends('admin.layout')

@section('title', 'Devices Management')

@section('content')
<div class="d-flex justify-content-between align-items-center mb-4">
    <h2>Devices</h2>
    <a href="#" class="btn btn-primary">Add Device</a>
</div>

<div class="card">
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-striped">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Name</th>
                        <th>Status</th>
                        <th>Owner</th>
                        <th>Last Seen</th>
                        <th>OS</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($devices as $device)
                    <tr>
                        <td>{{ $device->device_id }}</td>
                        <td>{{ $device->device_name ?? 'Unnamed' }}</td>
                        <td>
                            <span class="badge bg-{{ $device->lifecycle_state === 'online' ? 'success' : ($device->lifecycle_state === 'offline' ? 'secondary' : 'warning') }}">
                                {{ ucfirst($device->lifecycle_state ?? 'unknown') }}
                            </span>
                        </td>
                        <td>{{ $device->user->display_name ?? 'Unassigned' }}</td>
                        <td>{{ $device->last_seen ? $device->last_seen->diffForHumans() : 'Never' }}</td>
                        <td>{{ $device->os_build ?? 'Unknown' }}</td>
                        <td>
                            <a href="#" class="btn btn-sm btn-outline-primary">View</a>
                            <a href="#" class="btn btn-sm btn-outline-warning">Commands</a>
                            <a href="#" class="btn btn-sm btn-outline-danger">Delete</a>
                        </td>
                    </tr>
                    @endforeach
                </tbody>
            </table>
        </div>

        {{ $devices->links() }}
    </div>
</div>
@endsection
