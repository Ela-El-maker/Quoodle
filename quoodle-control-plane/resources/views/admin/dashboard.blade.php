@extends('admin.layout')

@section('title', 'Dashboard')

@section('styles')
    <style>
        :root {
            --primary-dark: #0f172a;
            --secondary-dark: #1e293b;
            --card-dark: #1e293b;
            --border-dark: #334155;
            --text-light: #f1f5f9;
            --text-muted: #94a3b8;
            --accent-blue: #3b82f6;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --info: #06b6d4;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }

        .stat-card {
            background-color: var(--card-dark);
            border: 1px solid var(--border-dark);
            border-radius: 0.5rem;
            padding: 1.5rem;
            transition: all 0.3s ease;
        }

        .stat-card:hover {
            border-color: var(--accent-blue);
            box-shadow: 0 10px 25px rgba(59, 130, 246, 0.1);
            transform: translateY(-2px);
        }

        .stat-icon {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 50px;
            height: 50px;
            border-radius: 0.5rem;
            margin-bottom: 1rem;
            font-size: 1.5rem;
        }

        .stat-icon.primary {
            background-color: rgba(59, 130, 246, 0.1);
            color: var(--accent-blue);
        }

        .stat-icon.success {
            background-color: rgba(16, 185, 129, 0.1);
            color: var(--success);
        }

        .stat-icon.info {
            background-color: rgba(6, 182, 212, 0.1);
            color: var(--info);
        }

        .stat-icon.warning {
            background-color: rgba(245, 158, 11, 0.1);
            color: var(--warning);
        }

        .stat-label {
            color: var(--text-muted);
            font-size: 0.875rem;
            font-weight: 500;
            margin-bottom: 0.5rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        .stat-value {
            font-size: 2rem;
            font-weight: 700;
            color: var(--text-light);
            margin-bottom: 0.5rem;
        }

        .stat-subtext {
            color: var(--text-muted);
            font-size: 0.875rem;
        }

        .content-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(500px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }

        .card-container {
            background-color: var(--card-dark);
            border: 1px solid var(--border-dark);
            border-radius: 0.5rem;
            overflow: hidden;
        }

        .card-header {
            padding: 1.5rem;
            border-bottom: 1px solid var(--border-dark);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .card-header h3 {
            margin: 0;
            font-size: 1.125rem;
            font-weight: 600;
            color: var(--text-light);
        }

        .card-body {
            padding: 1.5rem;
        }

        .chart-container {
            position: relative;
            height: 300px;
            margin: 0;
        }

        .list-group {
            list-style: none;
            padding: 0;
            margin: 0;
        }

        .list-item {
            padding: 1rem;
            border-bottom: 1px solid var(--border-dark);
            transition: background-color 0.2s ease;
        }

        .list-item:last-child {
            border-bottom: none;
        }

        .list-item:hover {
            background-color: rgba(59, 130, 246, 0.05);
        }

        .list-item-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 0.5rem;
        }

        .list-item-title {
            font-weight: 600;
            color: var(--text-light);
        }

        .list-item-time {
            color: var(--text-muted);
            font-size: 0.875rem;
        }

        .list-item-meta {
            color: var(--text-muted);
            font-size: 0.875rem;
            line-height: 1.5;
        }

        .table-container {
            overflow-x: auto;
        }

        .table {
            width: 100%;
            border-collapse: collapse;
            margin: 0;
        }

        .table thead {
            background-color: rgba(59, 130, 246, 0.05);
        }

        .table th {
            padding: 1rem;
            text-align: left;
            font-weight: 600;
            color: var(--text-light);
            border-bottom: 1px solid var(--border-dark);
            font-size: 0.875rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        .table td {
            padding: 1rem;
            border-bottom: 1px solid var(--border-dark);
            color: var(--text-light);
        }

        .table tbody tr {
            transition: background-color 0.2s ease;
        }

        .table tbody tr:hover {
            background-color: rgba(59, 130, 246, 0.05);
        }

        .badge {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.375rem 0.75rem;
            border-radius: 0.25rem;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        .badge.success {
            background-color: rgba(16, 185, 129, 0.1);
            color: var(--success);
        }

        .badge.warning {
            background-color: rgba(245, 158, 11, 0.1);
            color: var(--warning);
        }

        .badge.danger {
            background-color: rgba(239, 68, 68, 0.1);
            color: var(--danger);
        }

        .badge.info {
            background-color: rgba(6, 182, 212, 0.1);
            color: var(--info);
        }

        @media (max-width: 1024px) {
            .content-grid {
                grid-template-columns: 1fr;
            }
        }

        @media (max-width: 640px) {
            .stats-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
@endsection
@php
$deviceStatuses = $deviceStatuses ?? [
    'Online' => 45,
    'Offline' => 12,
    'Idle' => 8,
    'Error' => 3,
];
@endphp

@section('content')
    <!-- Stats Grid -->
    <div class="stats-grid">
        <!-- Total Users -->
        <div class="stat-card">
            <div class="stat-icon primary">
                <i class="fas fa-users"></i>
            </div>
            <div class="stat-label">Total Users</div>
            <div class="stat-value">{{ $stats['total_users'] ?? 0 }}</div>
            <div class="stat-subtext">Active users in system</div>
        </div>

        <!-- Active Devices -->
        <div class="stat-card">
            <div class="stat-icon success">
                <i class="fas fa-mobile-alt"></i>
            </div>
            <div class="stat-label">Active Devices</div>
            <div class="stat-value">{{ $stats['active_devices'] ?? 0 }}</div>
            <div class="stat-subtext">of {{ $stats['total_devices'] ?? 0 }} devices</div>
        </div>

        <!-- System Uptime -->
        <div class="stat-card">
            <div class="stat-icon info">
                <i class="fas fa-server"></i>
            </div>
            <div class="stat-label">System Uptime</div>
            <div class="stat-value">{{ $stats['uptime'] ?? '99.9' }}%</div>
            <div class="stat-subtext">No downtime today</div>
        </div>

        <!-- Pending Alerts -->
        <div class="stat-card">
            <div class="stat-icon warning">
                <i class="fas fa-exclamation-circle"></i>
            </div>
            <div class="stat-label">Pending Alerts</div>
            <div class="stat-value">{{ $stats['pending_alerts'] ?? 0 }}</div>
            <div class="stat-subtext">{{ $stats['unacknowledged_alerts'] ?? 0 }} unacknowledged</div>
        </div>
    </div>

    <!-- Content Grid -->
    <div class="content-grid">
        <!-- Device Status Distribution -->
        <div class="card-container">
            <div class="card-header">
                <h3>Device Status Distribution</h3>
            </div>
            <div class="card-body">
                <div class="chart-container">
                    <canvas id="deviceStatusChart"></canvas>
                </div>
            </div>
        </div>

        <!-- Recent Commands -->
        <div class="card-container">
            <div class="card-header">
                <h3>Recent Commands</h3>
            </div>
            <div class="card-body">
                <ul class="list-group">
                    @forelse($recentCommands ?? [] as $command)
                        <li class="list-item">
                            <div class="list-item-header">
                                <span class="list-item-title">{{ $command->method ?? 'Unknown' }}</span>
                                <span class="list-item-time">{{ $command->created_at->diffForHumans() ?? 'N/A' }}</span>
                            </div>
                            <div class="list-item-meta">
                                <div>Device:
                                    <strong>{{ $command->device->device_name ?? $command->device_id ?? 'N/A' }}</strong></div>
                                <div>User: <strong>{{ $command->user->display_name ?? $command->user_id ?? 'N/A' }}</strong>
                                </div>
                            </div>
                        </li>
                    @empty
                        <li class="list-item" style="text-align: center; color: var(--text-muted);">
                            No recent commands
                        </li>
                    @endforelse
                </ul>
            </div>
        </div>
    </div>

    <!-- Recent Alerts Table -->
    <div class="card-container">
        <div class="card-header">
            <h3>Recent Alerts</h3>
        </div>
        <div class="card-body">
            <div class="table-container">
                <table class="table">
                    <thead>
                        <tr>
                            <th>Time</th>
                            <th>Device</th>
                            <th>Type</th>
                            <th>Message</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($recentAlerts ?? [] as $alert)
                            <tr>
                                <td>{{ $alert->created_at->format('M d, H:i') ?? 'N/A' }}</td>
                                <td>{{ $alert->device->name ?? $alert->device_id ?? 'N/A' }}</td>
                                <td>
                                    <span class="badge {{ strtolower($alert->type ?? 'info') }}">
                                        {{ $alert->type ?? 'Info' }}
                                    </span>
                                </td>
                                <td>{{ $alert->message ?? 'N/A' }}</td>
                                <td>
                                    @if($alert->acknowledged_at ?? false)
                                        <span class="badge success">
                                            <i class="fas fa-check-circle"></i> Acknowledged
                                        </span>
                                    @else
                                        <span class="badge warning">
                                            <i class="fas fa-clock"></i> Pending
                                        </span>
                                    @endif
                                </td>
                            </tr>
                        @empty
                            <tr>
                                <td colspan="5" style="text-align: center; color: var(--text-muted); padding: 2rem;">
                                    No recent alerts
                                </td>
                            </tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
    </div>
@endsection

@section('scripts')
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <script>
        // Device Status Chart
        const deviceStatusCtx = document.getElementById('deviceStatusChart');
        if (deviceStatusCtx) {
            const deviceStatuses = @json($deviceStatuses);

            new Chart(deviceStatusCtx, {
                type: 'doughnut',
                data: {
                    labels: Object.keys(deviceStatuses),
                    datasets: [{
                        data: Object.values(deviceStatuses),
                        backgroundColor: [
                            '#10b981',
                            '#ef4444',
                            '#f59e0b',
                            '#06b6d4'
                        ],
                        borderColor: '#1e293b',
                        borderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                color: '#f1f5f9',
                                padding: 15,
                                font: {
                                    size: 12,
                                    weight: '600'
                                }
                            }
                        }
                    }
                }
            });
        }
    </script>
@endsection

