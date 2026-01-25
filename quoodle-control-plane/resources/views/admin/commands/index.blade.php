@extends('admin.layout')

@section('title', 'Commands Management')

@section('content')
<div class="d-flex justify-content-between align-items-center mb-4">
    <h2>Commands</h2>
    <a href="#" class="btn btn-primary">Execute Command</a>
</div>

<div class="card">
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-striped">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Method</th>
                        <th>Device</th>
                        <th>User</th>
                        <th>Status</th>
                        <th>Created</th>
                        <th>Completed</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($commands as $command)
                    <tr>
                        <td>{{ $command->id }}</td>
                        <td>{{ $command->method }}</td>
                        <td>{{ $command->device->device_name ?? $command->device_id }}</td>
                        <td>{{ $command->user->display_name ?? $command->user_id }}</td>
                        <td>
                            <span class="badge bg-{{ $command->status === 'completed' ? 'success' : ($command->status === 'failed' ? 'danger' : ($command->status === 'pending' ? 'warning' : 'secondary')) }}">
                                {{ ucfirst($command->status) }}
                            </span>
                        </td>
                        <td>{{ $command->created_at->format('M d, H:i') }}</td>
                        <td>{{ $command->completed_at ? $command->completed_at->format('M d, H:i') : '-' }}</td>
                        <td>
                            <a href="#" class="btn btn-sm btn-outline-primary">View Details</a>
                        </td>
                    </tr>
                    @endforeach
                </tbody>
            </table>
        </div>

        {{ $commands->links() }}
    </div>
</div>
@endsection
