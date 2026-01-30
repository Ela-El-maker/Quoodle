@extends('admin.layout')

@section('title', 'Users Management')

@section('content')
    <div class="bg-slate-950 p-4 md:p-8">
        <!-- Header -->
        <div class="mb-8">
            <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                <div>
                    <h1 class="text-4xl font-bold text-white mb-2">Users Management</h1>
                    <p class="text-slate-400">Manage and monitor all system users and their permissions</p>
                </div>
                <form method="GET" class="flex flex-wrap gap-2 items-center">
                    <input type="text" name="q" value="{{ $search ?? '' }}" class="form-control bg-slate-700/30 text-slate-200 border border-slate-600 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" placeholder="Search users...">
                    <select name="role" class="form-select bg-slate-700/30 text-slate-200 border border-slate-600 rounded-lg px-3 py-2 text-sm">
                        <option value="">All roles</option>
                        <option value="admin" @if(($role ?? '') === 'admin') selected @endif>Admin</option>
                        <option value="operator" @if(($role ?? '') === 'operator') selected @endif>Operator</option>
                        <option value="viewer" @if(($role ?? '') === 'viewer') selected @endif>Viewer</option>
                    </select>
                    <button class="inline-flex items-center gap-2 px-4 py-2 bg-blue-500/10 text-blue-400 border border-blue-500/20 hover:bg-blue-500/20 hover:text-blue-300 rounded-md text-sm font-medium transition-colors duration-150" type="submit">
                        Filter
                    </button>
                </form>
                <a href="#" class="inline-flex items-center gap-2 px-4 py-2
                          bg-blue-500/10 text-blue-400
                          border border-blue-500/20
                          hover:bg-blue-500/20 hover:text-blue-300
                          rounded-md text-sm font-medium
                          transition-colors duration-150">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    Add User
                </a>

            </div>
        </div>

        <!-- Users Table (Alerts-style layout) -->
        <div class="card-container">
            <div class="card-header">
                <h3>Users</h3>
            </div>

            <div class="card-body">
                <div class="table-container">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Email</th>
                                <th>Role</th>
                                <th>Devices</th>
                                <th>Mobile Devices</th>
                                <th>Last Mobile Seen</th>
                                <th>Status</th>
                            </tr>
                        </thead>

                        <tbody>
                            @forelse($users ?? [] as $user)
                                <tr>
                                    <!-- Name -->
                                    <td>
                                        {{ $user->display_name ?? 'N/A' }}
                                    </td>

                                    <!-- Email -->
                                    <td>
                                        {{ $user->email ?? 'N/A' }}
                                    </td>

                                    <!-- Role -->
                                    <td>
                                        <span class="badge {{ strtolower($user->role ?? 'user') }}">
                                            {{ ucfirst($user->role ?? 'User') }}
                                        </span>
                                    </td>

                                    <!-- Devices -->
                                    <td>
                                        {{ $user->devices->count() ?? 0 }}
                                    </td>

                                    <!-- Mobile Devices -->
                                    <td>
                                        {{ $user->mobileDevices->count() ?? 0 }}
                                    </td>

                                    <!-- Last Mobile Seen -->
                                    <td>
                                        @php
                                            $lastMobileSeen = $user->mobileDevices->max('last_seen_at');
                                        @endphp
                                        {{ $lastMobileSeen ? $lastMobileSeen->diffForHumans() : '—' }}
                                    </td>

                                    <!-- Status -->
                                    <td>
                                        @if($user->is_active ?? true)
                                            <span class="badge success">
                                                Active
                                            </span>
                                        @else
                                            <span class="badge warning">
                                                Disabled
                                            </span>
                                        @endif
                                    </td>
                                </tr>
                            @empty
                                <tr>
                                    <td colspan="7" style="text-align: center; color: var(--text-muted); padding: 2rem;">
                                        No users found
                                    </td>
                                </tr>
                            @endforelse
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

    </div>
@endsection
