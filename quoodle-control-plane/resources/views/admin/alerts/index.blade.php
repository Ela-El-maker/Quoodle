@extends('admin.layout')

@section('title', 'Alerts Management')

@section('content')
    <div class="mb-4 d-flex flex-wrap justify-content-between align-items-center gap-3">
        <div>
            <h2 class="mb-1">Alerts</h2>
            <p class="text-muted mb-0">Security and compliance signals across the fleet.</p>
        </div>
        <a href="#" class="btn btn-outline-info">Create Alert</a>
    </div>

    <div class="panel">
        <div class="panel-header">
            <h5 class="mb-0">Active alerts</h5>
            <form method="GET" class="d-flex gap-2">
                <input type="text" name="q" value="{{ $search }}" class="form-control form-control-sm bg-transparent text-white border-secondary" placeholder="Search device or category">
                <select name="severity" class="form-select form-select-sm bg-dark text-white border-secondary">
                    <option value="">All severities</option>
                    <option value="critical" @if($severity === 'critical') selected @endif>Critical</option>
                    <option value="high" @if($severity === 'high') selected @endif>High</option>
                    <option value="medium" @if($severity === 'medium') selected @endif>Medium</option>
                    <option value="low" @if($severity === 'low') selected @endif>Low</option>
                </select>
                <select name="status" class="form-select form-select-sm bg-dark text-white border-secondary">
                    <option value="">All status</option>
                    <option value="pending" @if($status === 'pending') selected @endif>Pending</option>
                    <option value="ack" @if($status === 'ack') selected @endif>Acknowledged</option>
                </select>
                <button class="btn btn-sm btn-outline-secondary" type="submit">Filter</button>
            </form>
        </div>
        <div class="panel-body table-responsive">
            <table class="table table-dark table-hover align-middle">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Category</th>
                        <th>Device</th>
                        <th>Message</th>
                        <th>Severity</th>
                        <th>Status</th>
                        <th>Created</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    @foreach($alerts as $alert)
                        <tr>
                            <td class="text-truncate" style="max-width: 140px;">{{ $alert->alert_id ?? $alert->id }}</td>
                            <td>{{ $alert->category }}</td>
                            <td>{{ $alert->device->device_name ?? $alert->device_id }}</td>
                            <td class="text-truncate" style="max-width: 240px;">{{ $alert->message }}</td>
                            <td>
                                <span class="badge-pill {{ $alert->severity === 'critical' ? 'badge-danger' : ($alert->severity === 'high' ? 'badge-warning' : ($alert->severity === 'medium' ? 'badge-info' : 'badge-muted')) }}">
                                    {{ ucfirst($alert->severity) }}
                                </span>
                            </td>
                            <td>
                                <span class="badge-pill {{ $alert->acknowledged ? 'badge-success' : 'badge-warning' }}">
                                    {{ $alert->acknowledged ? 'Acknowledged' : 'Pending' }}
                                </span>
                            </td>
                            <td>{{ $alert->created_at->format('M d, H:i') }}</td>
                            <td class="text-end">
                                @if(!$alert->acknowledged)
                                    <form method="POST" action="{{ route('admin.alerts.ack', $alert) }}" style="display:inline;">
                                        @csrf
                                        <button type="submit" class="btn btn-sm btn-outline-success">Acknowledge</button>
                                    </form>
                                @endif
                                <button type="button"
                                    class="btn btn-sm btn-outline-info"
                                    data-bs-toggle="modal"
                                    data-bs-target="#alertDetailModal"
                                    data-alert-id="{{ $alert->alert_id ?? $alert->id }}"
                                    data-alert-category="{{ $alert->category }}"
                                    data-alert-device="{{ $alert->device->device_name ?? $alert->device_id }}"
                                    data-alert-device-id="{{ $alert->device_id }}"
                                    data-alert-message="{{ $alert->message }}"
                                    data-alert-severity="{{ $alert->severity }}"
                                    data-alert-status="{{ $alert->acknowledged ? 'Acknowledged' : 'Pending' }}"
                                    data-alert-created="{{ $alert->created_at->format('M d, H:i') }}"
                                    data-alert-link="{{ route('admin.alerts.show', $alert) }}"
                                    data-alert-ack-url="{{ route('admin.alerts.ack', $alert) }}"
                                    data-alert-acknowledged="{{ $alert->acknowledged ? '1' : '0' }}"
                                    data-alert-device-link="{{ $alert->device ? route('admin.devices.show', $alert->device) : '' }}"
                                    data-alert-device-commands="{{ route('admin.commands', ['q' => $alert->device_id]) }}"
                                    data-alert-device-alerts="{{ route('admin.alerts', ['q' => $alert->device_id]) }}"
                                    data-alert-device-audit="{{ route('admin.audit', ['q' => $alert->device_id]) }}">
                                    View
                                </button>
                            </td>
                        </tr>
                    @endforeach
                </tbody>
            </table>

            {{ $alerts->links() }}
        </div>
    </div>

    <div class="modal fade" id="alertDetailModal" tabindex="-1" aria-labelledby="alertDetailModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg modal-dialog-centered">
            <div class="modal-content bg-dark text-white border-secondary">
                <div class="modal-header border-secondary">
                    <h5 class="modal-title" id="alertDetailModalLabel">Alert Detail</h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Alert ID</div>
                            <div class="fw-semibold" id="alertDetailId">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Created</div>
                            <div class="fw-semibold" id="alertDetailCreated">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Device</div>
                            <div class="fw-semibold" id="alertDetailDevice">—</div>
                            <div class="text-muted small" id="alertDetailDeviceId">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Category</div>
                            <div class="fw-semibold" id="alertDetailCategory">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Severity</div>
                            <span class="badge-pill badge-muted" id="alertDetailSeverity">—</span>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Status</div>
                            <span class="badge-pill badge-muted" id="alertDetailStatus">—</span>
                        </div>
                        <div class="col-12">
                            <div class="text-muted text-uppercase small">Message</div>
                            <div class="fw-semibold" id="alertDetailMessage">—</div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer border-secondary">
                    <form method="POST" id="alertDetailAckForm" action="#" class="me-auto">
                        @csrf
                        <button type="submit" class="btn btn-outline-success" id="alertDetailAckButton">Acknowledge</button>
                    </form>
                    <a class="btn btn-outline-primary" id="alertDetailDeviceLink" href="#">View device</a>
                    <a class="btn btn-outline-secondary" id="alertDetailCommandsLink" href="#">Device commands</a>
                    <a class="btn btn-outline-secondary" id="alertDetailAlertsLink" href="#">Device alerts</a>
                    <a class="btn btn-outline-secondary" id="alertDetailAuditLink" href="#">Audit trail</a>
                    <a class="btn btn-outline-info" id="alertDetailLink" href="#">Open full alert</a>
                    <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Close</button>
                </div>
            </div>
        </div>
    </div>

    <script>
        const alertDetailModal = document.getElementById('alertDetailModal');
        if (alertDetailModal) {
            alertDetailModal.addEventListener('show.bs.modal', event => {
                const trigger = event.relatedTarget;
                if (!trigger) return;
                const get = name => trigger.getAttribute(name) || '—';
                const severity = get('data-alert-severity');
                const status = get('data-alert-status');
                document.getElementById('alertDetailId').textContent = get('data-alert-id');
                document.getElementById('alertDetailCategory').textContent = get('data-alert-category');
                document.getElementById('alertDetailDevice').textContent = get('data-alert-device');
                document.getElementById('alertDetailDeviceId').textContent = get('data-alert-device-id');
                document.getElementById('alertDetailMessage').textContent = get('data-alert-message');
                document.getElementById('alertDetailCreated').textContent = get('data-alert-created');
                const severityBadge = document.getElementById('alertDetailSeverity');
                severityBadge.textContent = severity ? severity.charAt(0).toUpperCase() + severity.slice(1) : '—';
                severityBadge.className = `badge-pill ${severity === 'critical' ? 'badge-danger' : (severity === 'high' ? 'badge-warning' : (severity === 'medium' ? 'badge-info' : 'badge-muted'))}`;
                const statusBadge = document.getElementById('alertDetailStatus');
                statusBadge.textContent = status;
                statusBadge.className = `badge-pill ${status === 'Acknowledged' ? 'badge-success' : 'badge-warning'}`;
                document.getElementById('alertDetailLink').setAttribute('href', get('data-alert-link'));
                const ackForm = document.getElementById('alertDetailAckForm');
                const ackButton = document.getElementById('alertDetailAckButton');
                const isAck = get('data-alert-acknowledged') === '1';
                ackForm.setAttribute('action', get('data-alert-ack-url'));
                ackButton.classList.toggle('d-none', isAck);
                const deviceLink = document.getElementById('alertDetailDeviceLink');
                const deviceHref = get('data-alert-device-link');
                deviceLink.setAttribute('href', deviceHref || '#');
                deviceLink.classList.toggle('disabled', !deviceHref);
                document.getElementById('alertDetailCommandsLink').setAttribute('href', get('data-alert-device-commands'));
                document.getElementById('alertDetailAlertsLink').setAttribute('href', get('data-alert-device-alerts'));
                document.getElementById('alertDetailAuditLink').setAttribute('href', get('data-alert-device-audit'));
            });
        }
    </script>
@endsection
