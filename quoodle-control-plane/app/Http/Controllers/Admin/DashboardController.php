<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\Device;
use App\Models\Command;
use App\Models\Alert;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    public function index()
    {
        // Overview stats
        $stats = [
            'total_users' => User::count(),
            'total_devices' => Device::count(),
            'active_devices' => Device::where('last_seen', '>', now()->subMinutes(5))->count(),
            'total_commands' => Command::count(),
            'pending_commands' => Command::where('status', 'pending')->count(),
            'total_alerts' => Alert::count(),
            'unacknowledged_alerts' => Alert::where('acknowledged', false)->count(),
        ];

        // Recent activity
        $recentCommands = Command::with(['device', 'user'])
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();

        $recentAlerts = Alert::with('device')
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();

        $deviceStatuses = Device::select('lifecycle_state', DB::raw('count(*) as count'))
            ->groupBy('lifecycle_state')
            ->get()
            ->pluck('count', 'lifecycle_state');

        return view('admin.dashboard', compact('stats', 'recentCommands', 'recentAlerts', 'deviceStatuses'));
    }

    public function users()
    {
        $users = User::with('devices')->paginate(20);
        return view('admin.users.index', compact('users'));
    }

    public function devices()
    {
        $devices = Device::with('user')->paginate(20);
        return view('admin.devices.index', compact('devices'));
    }

    public function commands()
    {
        $commands = Command::with(['device', 'user'])
            ->orderBy('created_at', 'desc')
            ->paginate(20);
        return view('admin.commands.index', compact('commands'));
    }

    public function alerts()
    {
        $alerts = Alert::with('device')
            ->orderBy('created_at', 'desc')
            ->paginate(20);
        return view('admin.alerts.index', compact('alerts'));
    }

    public function audit()
    {
        // This would need to be implemented based on audit logs
        $auditLogs = []; // Placeholder
        return view('admin.audit.index', compact('auditLogs'));
    }
}
