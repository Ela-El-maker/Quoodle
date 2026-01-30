@extends('admin.layout')

@section('title', 'Commands Management')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Command Center</h2>
            <p class="text-muted mb-0">Track command intent, dispatch, acknowledgements, and signed results.</p>
        </div>
        <div class="d-flex flex-wrap gap-2">
            <a class="btn btn-outline-secondary" href="{{ route('admin.commands.export') }}">Export CSV</a>
            <button class="btn btn-outline-info" data-bs-toggle="modal" data-bs-target="#commandModal">New Command</button>
        </div>
    </div>

    <div class="row g-4 mb-4">
        <div class="col-md-3">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Total</div>
                <div class="display-6 fw-bold">{{ $commandStats['total'] ?? 0 }}</div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Pending</div>
                <div class="display-6 fw-bold">{{ $commandStats['pending'] ?? 0 }}</div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Completed</div>
                <div class="display-6 fw-bold">{{ $commandStats['completed'] ?? 0 }}</div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="panel panel-body">
                <div class="text-muted text-uppercase small">Failed</div>
                <div class="display-6 fw-bold">{{ $commandStats['failed'] ?? 0 }}</div>
            </div>
        </div>
    </div>

    <div class="panel">
        <div class="panel-header">
            <h5 class="mb-0">Recent commands</h5>
            <form method="GET" class="d-flex gap-2">
                <input type="text" name="q" value="{{ $search }}" class="form-control form-control-sm bg-transparent text-white border-secondary" placeholder="Search ID, method, or device">
                <button class="btn btn-sm btn-outline-secondary" type="submit">Filter</button>
            </form>
        </div>
        <div class="panel-body table-responsive">
            <table class="table table-dark table-hover align-middle">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Method</th>
                        <th>Device</th>
                        <th>User</th>
                        <th>Status</th>
                        <th>Queued</th>
                        <th>Completed</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($commands as $command)
                        @php
                            $state = $command->state ?? $command->status ?? 'unknown';
                            $badgeClass = 'badge-muted';
                            if (in_array($state, ['completed'], true)) {
                                $badgeClass = 'badge-success';
                            } elseif (in_array($state, ['failed', 'rejected', 'expired'], true)) {
                                $badgeClass = 'badge-danger';
                            } elseif (in_array($state, ['dispatched', 'ack_received', 'executing'], true)) {
                                $badgeClass = 'badge-info';
                            } elseif (in_array($state, ['queued', 'pending'], true)) {
                                $badgeClass = 'badge-warning';
                            }
                        @endphp
                        <tr>
                            <td class="text-truncate" style="max-width: 140px;">{{ $command->id }}</td>
                            <td>{{ $command->method }}</td>
                            <td>{{ $command->device->device_name ?? $command->device_id }}</td>
                            <td>{{ $command->user->display_name ?? $command->user_id }}</td>
                            <td>
                                <span class="badge-pill {{ $badgeClass }}">
                                    {{ ucfirst($state) }}
                                </span>
                            </td>
                            <td>{{ optional($command->queued_at ?? $command->created_at)->format('M d, H:i') }}</td>
                            <td>{{ $command->completed_at ? $command->completed_at->format('M d, H:i') : '-' }}</td>
                            <td class="text-end">
                                <a href="{{ route('admin.commands.show', $command) }}" class="btn btn-sm btn-outline-info">View Timeline</a>
                            </td>
                        </tr>
                    @endforeach
                </tbody>
            </table>

            {{ $commands->links() }}
        </div>
    </div>

    <div class="modal fade" id="commandModal" tabindex="-1" aria-labelledby="commandModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg modal-dialog-centered">
            <div class="modal-content bg-dark text-white border-secondary">
                <div class="modal-header border-secondary">
                    <h5 class="modal-title" id="commandModalLabel">Execute Command</h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <form method="POST" action="{{ route('admin.commands.execute') }}">
                    @csrf
                    <div class="modal-body">
                        @if($errors->has('execute'))
                            <div class="alert alert-danger">{{ $errors->first('execute') }}</div>
                        @endif
                        <div class="mb-3">
                            <label class="form-label">Device</label>
                            <select name="device_id" class="form-select bg-dark text-white border-secondary" required>
                                <option value="">Select device</option>
                                @foreach($devices as $device)
                                    <option value="{{ $device->device_id }}">{{ $device->device_name ?? $device->device_id }}</option>
                                @endforeach
                            </select>
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Method</label>
                            <input type="text" name="method" class="form-control bg-dark text-white border-secondary" placeholder="lock_screen" required>
                        </div>
                        <div class="mb-3">
                            <label class="form-label">Params (JSON)</label>
                            <textarea name="params" class="form-control bg-dark text-white border-secondary" rows="3" placeholder='{"reason":"policy"}'></textarea>
                        </div>
                        <div class="form-check mb-3">
                            <input class="form-check-input" type="checkbox" value="1" id="sensitiveCheck" name="sensitive">
                            <label class="form-check-label" for="sensitiveCheck">Sensitive command (requires 2FA)</label>
                        </div>
                        <div class="mb-3">
                            <label class="form-label">2FA Code (optional)</label>
                            <input type="text" name="two_factor_code" class="form-control bg-dark text-white border-secondary" placeholder="123456">
                        </div>
                    </div>
                    <div class="modal-footer border-secondary">
                        <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancel</button>
                        <button type="submit" class="btn btn-info">Execute</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
@endsection
