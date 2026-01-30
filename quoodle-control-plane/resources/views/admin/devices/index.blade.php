@extends('admin.layout')

@section('title', 'Devices Management')

@section('content')
    <div class="min-h-screen bg-gradient-to-br from-slate-950 to-slate-900 p-4 md:p-8">

        <!-- Header -->
        <div class="mb-8">
            <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                <div>
                    <h1 class="text-4xl font-bold text-white mb-2">Devices Management</h1>
                    <p class="text-slate-400">Monitor and manage all connected devices</p>
                </div>

                <button type="button" class="inline-flex items-center justify-center px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-blue-400" aria-label="Add Device" onclick="alert('Add Device modal coming soon!')">
                    <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
                    </svg>
                    Add Device
                </button>
            </div>
        </div>

        <!-- Fleet Stats -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <div class="panel panel-body">
                <div class="text-xs uppercase text-slate-400">Total Devices</div>
                <div class="text-2xl font-semibold text-white">{{ $fleetStats['total'] ?? 0 }}</div>
            </div>
            <div class="panel panel-body">
                <div class="text-xs uppercase text-slate-400">Online</div>
                <div class="text-2xl font-semibold text-emerald-400">{{ $fleetStats['online'] ?? 0 }}</div>
            </div>
            <div class="panel panel-body">
                <div class="text-xs uppercase text-slate-400">Quarantined</div>
                <div class="text-2xl font-semibold text-amber-300">{{ $fleetStats['quarantined'] ?? 0 }}</div>
            </div>
            <div class="panel panel-body">
                <div class="text-xs uppercase text-slate-400">At Risk</div>
                <div class="text-2xl font-semibold text-rose-400">{{ $fleetStats['at_risk'] ?? 0 }}</div>
            </div>
        </div>

        <!-- Devices Table Card -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl shadow-lg overflow-hidden">

            <!-- Card Header -->
            <div class="px-4 md:px-8 py-4 md:py-6 border-b border-slate-700 bg-slate-800/50 flex flex-col md:flex-row md:items-center md:justify-between gap-2">
                <h2 class="text-lg font-semibold text-white mb-2 md:mb-0">All Devices</h2>
                <form method="GET">
                    <input type="text" name="q" value="{{ $search }}" class="form-control w-full md:w-64 bg-slate-700/30 text-slate-200 border border-slate-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" placeholder="Search devices..." aria-label="Search devices">
                </form>
            </div>

            <!-- Table -->
            <div class="overflow-x-auto">
                <table class="w-full text-sm" id="devicesTable">
                    <thead class="bg-slate-700/50 border-b border-slate-700">
                        <tr>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(0)">Device <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(1)">Status <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(2)">Owner <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(3)">Compliance <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(4)">Risk <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(5)">OS <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-left font-semibold text-slate-300 cursor-pointer" onclick="sortDeviceTable(6)">Last Seen <span class="sort-indicator"></span></th>
                            <th class="px-8 py-4 text-right font-semibold text-slate-300">Actions</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-slate-700 text-slate-300">
                        @forelse($devices as $device)
                            <tr class="hover:bg-slate-700/30 transition-colors align-middle">
                                <td class="px-8 py-4 font-medium text-white">
                                    <div class="inline-flex items-center gap-3 whitespace-nowrap">
                                        <div class="w-9 h-9 rounded-lg bg-slate-700/50 flex items-center justify-center" aria-label="Device icon">
                                            <svg class="w-5 h-5 text-blue-400 flex-shrink-0" style="width:20px;height:20px"
                                                fill="currentColor" viewBox="0 0 20 20">
                                                <path d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4z" />
                                            </svg>
                                        </div>
                                        <span>{{ $device->device_name ?? 'Unnamed Device' }}</span>
                                    </div>
                                </td>
                                <td class="px-8 py-4">
                                    @if($device->lifecycle_state === 'online' || $device->lifecycle_state === 'active')
                                        <span class="inline-flex items-center gap-2 whitespace-nowrap">
                                            <span class="w-2 h-2 rounded-full bg-green-500"></span>
                                            <span class="text-green-400">Online</span>
                                        </span>
                                    @elseif($device->lifecycle_state === 'offline')
                                        <span class="inline-flex items-center gap-2 whitespace-nowrap">
                                            <span class="w-2 h-2 rounded-full bg-slate-500"></span>
                                            <span class="text-slate-400">Offline</span>
                                        </span>
                                    @elseif($device->lifecycle_state === 'pending_pairing')
                                        <span class="inline-flex items-center gap-2 whitespace-nowrap">
                                            <span class="w-2 h-2 rounded-full bg-amber-500"></span>
                                            <span class="text-amber-400">Pending pairing</span>
                                        </span>
                                    @elseif($device->lifecycle_state === 'quarantined')
                                        <span class="inline-flex items-center gap-2 whitespace-nowrap">
                                            <span class="w-2 h-2 rounded-full bg-red-500"></span>
                                            <span class="text-red-400">Quarantined</span>
                                        </span>
                                    @else
                                        <span class="inline-flex items-center gap-2 whitespace-nowrap">
                                            <span class="w-2 h-2 rounded-full bg-amber-500"></span>
                                            <span class="text-amber-400">
                                                {{ ucfirst($device->lifecycle_state ?? 'Unknown') }}
                                            </span>
                                        </span>
                                    @endif
                                </td>
                                <td class="px-8 py-4 text-slate-400 whitespace-nowrap">
                                    {{ $device->user->display_name ?? 'Unassigned' }}
                                </td>
                                <td class="px-8 py-4 text-slate-400 whitespace-nowrap">
                                    @php
                                        $compliance = strtolower($device->compliance_status ?? 'unknown');
                                        $complianceClass = 'badge info';
                                        if ($compliance === 'compliant') {
                                            $complianceClass = 'badge success';
                                        } elseif ($compliance === 'non-compliant' || $compliance === 'failed') {
                                            $complianceClass = 'badge danger';
                                        } elseif ($compliance === 'degraded') {
                                            $complianceClass = 'badge warning';
                                        } elseif ($compliance === 'quarantined') {
                                            $complianceClass = 'badge warning';
                                        }
                                    @endphp
                                    <span class="{{ $complianceClass }}">
                                        {{ ucfirst($device->compliance_status ?? 'Unknown') }}
                                    </span>
                                </td>
                                <td class="px-8 py-4 text-slate-400 whitespace-nowrap">
                                    {{ $device->risk_score ?? '-' }}
                                </td>
                                <td class="px-8 py-4 text-slate-400 whitespace-nowrap">
                                    {{ $device->os_build ?? 'Unknown' }}
                                </td>
                                <td class="px-8 py-4 text-slate-400 whitespace-nowrap">
                                    {{ $device->last_seen ? $device->last_seen->diffForHumans() : 'Never' }}
                                </td>
                                <td class="px-8 py-4 text-right">
                                    <div class="flex items-center justify-end gap-2">
                                        <button type="button"
                                            class="inline-flex items-center px-3 py-2 rounded-lg text-slate-300 hover:bg-blue-500/20 hover:text-blue-400 transition-colors duration-150 text-xs font-medium focus:outline-none focus:ring-2 focus:ring-blue-400"
                                            aria-label="View device"
                                            data-bs-toggle="modal"
                                            data-bs-target="#deviceDetailModal"
                                            data-device-id="{{ $device->device_id }}"
                                            data-device-name="{{ $device->device_name ?? 'Unnamed Device' }}"
                                            data-device-owner="{{ $device->user->display_name ?? 'Unassigned' }}"
                                            data-device-status="{{ ucfirst($device->lifecycle_state ?? 'Unknown') }}"
                                            data-device-compliance="{{ ucfirst($device->compliance_status ?? 'Unknown') }}"
                                            data-device-risk="{{ $device->risk_score ?? '-' }}"
                                            data-device-os="{{ $device->os_build ?? 'Unknown' }}"
                                            data-device-last-seen="{{ $device->last_seen ? $device->last_seen->diffForHumans() : 'Never' }}"
                                            data-device-link="{{ route('admin.devices.show', $device) }}"
                                            data-device-commands-link="{{ route('admin.commands', ['q' => $device->device_id]) }}"
                                            data-device-alerts-link="{{ route('admin.alerts', ['q' => $device->device_id]) }}"
                                            data-device-audit-link="{{ route('admin.audit', ['q' => $device->device_id]) }}">
                                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7" />
                                            </svg>
                                            View
                                        </button>
                                        <button type="button"
                                            class="inline-flex items-center px-3 py-2 rounded-lg text-slate-300 hover:bg-purple-500/20 hover:text-purple-400 transition-colors duration-150 text-xs font-medium focus:outline-none focus:ring-2 focus:ring-purple-400"
                                            aria-label="Device commands"
                                            data-bs-toggle="modal"
                                            data-bs-target="#deviceCommandsModal"
                                            data-device-id="{{ $device->device_id }}"
                                            data-device-name="{{ $device->device_name ?? 'Unnamed Device' }}"
                                            data-device-status="{{ ucfirst($device->lifecycle_state ?? 'Unknown') }}"
                                            data-device-link="{{ route('admin.devices.show', $device) }}"
                                            data-device-commands-link="{{ route('admin.commands', ['q' => $device->device_id]) }}"
                                            data-device-alerts-link="{{ route('admin.alerts', ['q' => $device->device_id]) }}"
                                            data-device-audit-link="{{ route('admin.audit', ['q' => $device->device_id]) }}">
                                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                                            </svg>
                                            Commands
                                        </button>
                                        <button type="button" class="inline-flex items-center px-3 py-2 rounded-lg text-slate-300 hover:bg-red-500/20 hover:text-red-400 transition-colors duration-150 text-xs font-medium focus:outline-none focus:ring-2 focus:ring-red-400" aria-label="Delete device" onclick="if(confirm('Are you sure you want to delete this device?')){alert('Delete device action coming soon!');}">
                                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862" />
                                            </svg>
                                            Delete
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        @empty
                            <tr>
                                <td colspan="8" class="px-8 py-12 text-center text-slate-400">
                                    <div class="inline-flex flex-col items-center gap-3">
                                        <svg class="w-12 h-12 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.75 17L4 12.25m0 0L9.75 7.5M4 12.25h16.25" />
                                        </svg>
                                        <p class="text-slate-400 font-medium">No devices found</p>
                                        <button type="button" class="mt-4 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium text-sm transition-colors duration-200" onclick="alert('Add Device modal coming soon!')">Add Device</button>
                                    </div>
                                </td>
                            </tr>
                        @endforelse
                    </tbody>
                </table>
            </div>

            <!-- Pagination -->
            @if($devices->hasPages())
                <div class="px-4 md:px-8 py-4 md:py-6 bg-slate-800/50 border-t border-slate-700">
                    {{ $devices->links() }}
                </div>
            @endif
        </div>
    </div>

    <div class="modal fade" id="deviceDetailModal" tabindex="-1" aria-labelledby="deviceDetailModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg modal-dialog-centered">
            <div class="modal-content bg-dark text-white border-secondary">
                <div class="modal-header border-secondary">
                    <h5 class="modal-title" id="deviceDetailModalLabel">Device Detail</h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Device</div>
                            <div class="fw-semibold" id="deviceDetailName">—</div>
                            <div class="text-muted small" id="deviceDetailId">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Owner</div>
                            <div class="fw-semibold" id="deviceDetailOwner">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Status</div>
                            <span class="badge-pill badge-muted" id="deviceDetailStatus">—</span>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Compliance</div>
                            <span class="badge-pill badge-muted" id="deviceDetailCompliance">—</span>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Risk Score</div>
                            <div class="fw-semibold" id="deviceDetailRisk">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">OS Build</div>
                            <div class="fw-semibold" id="deviceDetailOS">—</div>
                        </div>
                        <div class="col-md-6">
                            <div class="text-muted text-uppercase small">Last Seen</div>
                            <div class="fw-semibold" id="deviceDetailLastSeen">—</div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer border-secondary">
                    <a class="btn btn-outline-secondary" id="deviceDetailCommandsLink" href="#">Device commands</a>
                    <a class="btn btn-outline-secondary" id="deviceDetailAlertsLink" href="#">Device alerts</a>
                    <a class="btn btn-outline-secondary" id="deviceDetailAuditLink" href="#">Audit trail</a>
                    <a class="btn btn-outline-info" id="deviceDetailLink" href="#">Open full profile</a>
                    <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Close</button>
                </div>
            </div>
        </div>
    </div>

    <div class="modal fade" id="deviceCommandsModal" tabindex="-1" aria-labelledby="deviceCommandsModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg modal-dialog-centered">
            <div class="modal-content bg-dark text-white border-secondary">
                <div class="modal-header border-secondary">
                    <h5 class="modal-title" id="deviceCommandsModalLabel">Device Command Shortcuts</h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="mb-3">
                        <div class="text-muted text-uppercase small">Device</div>
                        <div class="fw-semibold" id="deviceCommandsName">—</div>
                        <div class="text-muted small" id="deviceCommandsId">—</div>
                    </div>
                    <div class="row g-3">
                        <div class="col-md-6">
                            <div class="panel panel-body">
                                <div class="text-muted text-uppercase small">Status</div>
                                <div class="fw-semibold" id="deviceCommandsStatus">—</div>
                                <div class="text-muted small mt-2">Quick links to fleet activity for this device.</div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="panel panel-body">
                                <div class="text-muted text-uppercase small">Suggested actions</div>
                                <ul class="list-unstyled mb-0 mt-2 small">
                                    <li>Open command history</li>
                                    <li>Review alerts and compliance notes</li>
                                    <li>Trace audit trail for this device</li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer border-secondary">
                    <a class="btn btn-outline-secondary" id="deviceCommandsHistoryLink" href="#">Open commands</a>
                    <a class="btn btn-outline-secondary" id="deviceCommandsAlertsLink" href="#">Open alerts</a>
                    <a class="btn btn-outline-secondary" id="deviceCommandsAuditLink" href="#">Open audit trail</a>
                    <a class="btn btn-outline-info" id="deviceCommandsProfileLink" href="#">Open device profile</a>
                    <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Close</button>
                </div>
            </div>
        </div>
    </div>
<style>
    .pagination {
        display: flex;
        gap: 0.5rem;
        justify-content: center;
        flex-wrap: wrap;
    }
    .pagination a,
    .pagination span {
        padding: 0.5rem 0.75rem;
        border-radius: 0.375rem;
        font-size: 0.875rem;
        font-weight: 500;
        transition: all 0.2s;
    }
    .pagination a {
        background-color: rgba(71, 85, 105, 0.3);
        color: #cbd5e1;
        border: 1px solid rgba(71, 85, 105, 0.5);
    }
    .pagination a:hover {
        background-color: rgba(37, 99, 235, 0.2);
        color: #60a5fa;
        border-color: rgba(37, 99, 235, 0.3);
    }
    .pagination .active span {
        background-color: #2563eb;
        color: white;
    }
    .pagination .disabled span {
        color: #64748b;
        cursor: not-allowed;
    }
    .sort-indicator {
        display: inline-block;
        width: 0;
        height: 0;
        margin-left: 4px;
        vertical-align: middle;
        border-left: 4px solid transparent;
        border-right: 4px solid transparent;
        border-top: 6px solid #94a3b8;
        opacity: 0.5;
    }
    th.sorted-asc .sort-indicator {
        border-top: none;
        border-bottom: 6px solid #2563eb;
        opacity: 1;
    }
    th.sorted-desc .sort-indicator {
        border-top: 6px solid #2563eb;
        opacity: 1;
    }
</style>
<script>
    // Table sorting (client-side)
    let sortDeviceDirection = {};
    function sortDeviceTable(colIdx) {
        const table = document.getElementById('devicesTable');
        const tbody = table.querySelector('tbody');
        const rows = Array.from(tbody.querySelectorAll('tr')).filter(row => !row.classList.contains('no-sort'));
        const ths = table.querySelectorAll('th');
        ths.forEach((th, idx) => th.classList.remove('sorted-asc', 'sorted-desc'));
        sortDeviceDirection[colIdx] = !sortDeviceDirection[colIdx];
        rows.sort((a, b) => {
            let aText = a.children[colIdx].innerText.trim().toLowerCase();
            let bText = b.children[colIdx].innerText.trim().toLowerCase();
            if (!isNaN(aText) && !isNaN(bText)) {
                aText = parseFloat(aText);
                bText = parseFloat(bText);
            }
            if (aText < bText) return sortDeviceDirection[colIdx] ? -1 : 1;
            if (aText > bText) return sortDeviceDirection[colIdx] ? 1 : -1;
            return 0;
        });
        rows.forEach(row => tbody.appendChild(row));
        ths[colIdx].classList.add(sortDeviceDirection[colIdx] ? 'sorted-asc' : 'sorted-desc');
    }
    // Server-side filtering enabled; keep sort only.

    const deviceDetailModal = document.getElementById('deviceDetailModal');
    if (deviceDetailModal) {
        deviceDetailModal.addEventListener('show.bs.modal', event => {
            const trigger = event.relatedTarget;
            if (!trigger) return;
            const get = name => trigger.getAttribute(name) || '—';
            document.getElementById('deviceDetailName').textContent = get('data-device-name');
            document.getElementById('deviceDetailId').textContent = get('data-device-id');
            document.getElementById('deviceDetailOwner').textContent = get('data-device-owner');
            document.getElementById('deviceDetailRisk').textContent = get('data-device-risk');
            document.getElementById('deviceDetailOS').textContent = get('data-device-os');
            document.getElementById('deviceDetailLastSeen').textContent = get('data-device-last-seen');
            const statusRaw = get('data-device-status');
            const status = statusRaw.toLowerCase() === 'active' ? 'Online' : statusRaw;
            const compliance = get('data-device-compliance');
            const statusBadge = document.getElementById('deviceDetailStatus');
            statusBadge.textContent = status;
            statusBadge.className = `badge-pill ${status === 'Online' ? 'badge-success' : (status === 'Offline' ? 'badge-muted' : 'badge-warning')}`;
            const complianceBadge = document.getElementById('deviceDetailCompliance');
            complianceBadge.textContent = compliance;
            const complianceLower = compliance.toLowerCase();
            complianceBadge.className = `badge-pill ${complianceLower === 'compliant' ? 'badge-success' : (complianceLower === 'non-compliant' || complianceLower === 'failed' ? 'badge-danger' : (complianceLower === 'degraded' || complianceLower === 'quarantined' ? 'badge-warning' : 'badge-muted'))}`;
            document.getElementById('deviceDetailLink').setAttribute('href', get('data-device-link'));
            document.getElementById('deviceDetailCommandsLink').setAttribute('href', get('data-device-commands-link'));
            document.getElementById('deviceDetailAlertsLink').setAttribute('href', get('data-device-alerts-link'));
            document.getElementById('deviceDetailAuditLink').setAttribute('href', get('data-device-audit-link'));
        });
    }

    const deviceCommandsModal = document.getElementById('deviceCommandsModal');
    if (deviceCommandsModal) {
        deviceCommandsModal.addEventListener('show.bs.modal', event => {
            const trigger = event.relatedTarget;
            if (!trigger) return;
            const get = name => trigger.getAttribute(name) || '—';
            document.getElementById('deviceCommandsName').textContent = get('data-device-name');
            document.getElementById('deviceCommandsId').textContent = get('data-device-id');
            const commandsStatusRaw = get('data-device-status');
            const commandsStatus = commandsStatusRaw.toLowerCase() === 'active' ? 'Online' : commandsStatusRaw;
            document.getElementById('deviceCommandsStatus').textContent = commandsStatus;
            document.getElementById('deviceCommandsHistoryLink').setAttribute('href', get('data-device-commands-link'));
            document.getElementById('deviceCommandsAlertsLink').setAttribute('href', get('data-device-alerts-link'));
            document.getElementById('deviceCommandsAuditLink').setAttribute('href', get('data-device-audit-link'));
            document.getElementById('deviceCommandsProfileLink').setAttribute('href', get('data-device-link'));
        });
    }
</script>
@endsection
