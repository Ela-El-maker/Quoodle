<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>@yield('title', 'Admin Dashboard') - Quoodle</title>

    <!-- Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&family=Sora:wght@500;600;700&display=swap" rel="stylesheet">
    <!-- Tailwind (utility classes for existing views) -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">

    <style>
        :root {
            --primary-dark: #0b1020;
            --secondary-dark: #121a2d;
            --card-dark: rgba(20, 30, 52, 0.85);
            --border-dark: rgba(64, 85, 125, 0.35);
            --text-light: #f1f5f9;
            --text-muted: #94a3b8;
            --accent-blue: #44c0ff;
            --accent-blue-dark: #1b5fbf;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --info: #06b6d4;
            --glass: rgba(255, 255, 255, 0.06);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            background: radial-gradient(circle at top left, #14213d 0%, #0b1020 45%, #070b16 100%);
            color: var(--text-light);
            font-family: 'Manrope', sans-serif;
            overflow-x: hidden;
        }

        h1, h2, h3, h4, h5, h6 {
            font-family: 'Sora', sans-serif;
            letter-spacing: -0.02em;
        }

        /* Sidebar Styles */
        .sidebar {
            position: fixed;
            top: 0;
            left: 0;
            width: 250px;
            height: 100vh;
            background: linear-gradient(180deg, rgba(17, 27, 49, 0.96) 0%, rgba(12, 17, 32, 0.98) 100%);
            border-right: 1px solid var(--border-dark);
            overflow-y: auto;
            z-index: 1000;
            transition: transform 0.3s ease;
            backdrop-filter: blur(14px);
        }

        .sidebar-header {
            padding: 1.5rem;
            border-bottom: 1px solid var(--border-dark);
        }

        .sidebar-brand {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            font-size: 1.25rem;
            font-weight: 700;
            color: var(--accent-blue);
            text-decoration: none;
        }

        .sidebar-brand i {
            font-size: 1.5rem;
        }

        .nav-menu {
            padding: 1rem 0;
            list-style: none;
        }

        .nav-item {
            margin: 0.25rem 0;
        }

        .nav-link {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.75rem 1.5rem;
            color: var(--text-muted);
            text-decoration: none;
            transition: all 0.2s ease;
            border-left: 3px solid transparent;
        }

        .nav-link:hover {
            background-color: rgba(59, 130, 246, 0.1);
            color: var(--text-light);
            border-left-color: var(--accent-blue);
        }

        .nav-link.active {
            background-color: rgba(59, 130, 246, 0.1);
            color: var(--accent-blue);
            border-left-color: var(--accent-blue);
        }

        .nav-link i {
            width: 20px;
            text-align: center;
        }

        /* Main Content Styles */
        .main-wrapper {
            margin-left: 250px;
            display: flex;
            flex-direction: column;
            min-height: 100vh;
        }

        .topbar {
            background-color: rgba(17, 26, 45, 0.85);
            border-bottom: 1px solid var(--border-dark);
            padding: 1rem 2rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            position: sticky;
            top: 0;
            z-index: 500;
            backdrop-filter: blur(16px);
        }

        .topbar-title {
            font-size: 1.5rem;
            font-weight: 600;
            color: var(--text-light);
            margin: 0;
        }

        .topbar-right {
            display: flex;
            align-items: center;
            gap: 1.5rem;
        }

        .user-info {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.5rem 1rem;
            background-color: rgba(68, 192, 255, 0.08);
            border-radius: 0.375rem;
        }

        .user-name {
            color: var(--text-light);
            font-size: 0.9rem;
        }

        .logout-btn {
            background-color: var(--danger);
            color: white;
            border: none;
            padding: 0.5rem 1rem;
            border-radius: 0.375rem;
            font-size: 0.875rem;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s ease;
            text-decoration: none;
        }

        .logout-btn:hover {
            background-color: #dc2626;
            color: white;
        }

        /* Content Area */
        .content-area {
            flex: 1;
            padding: 2rem;
            overflow-y: auto;
        }

        .panel {
            background: var(--card-dark);
            border: 1px solid var(--border-dark);
            border-radius: 16px;
            backdrop-filter: blur(18px);
            box-shadow: 0 18px 40px rgba(15, 23, 42, 0.35);
        }

        .panel-header {
            padding: 1.25rem 1.5rem;
            border-bottom: 1px solid var(--border-dark);
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .panel-body {
            padding: 1.5rem;
        }

        .badge-pill {
            padding: 0.25rem 0.6rem;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.08em;
        }

        .badge-success { background: rgba(16, 185, 129, 0.15); color: #34d399; }
        .badge-warning { background: rgba(245, 158, 11, 0.15); color: #fbbf24; }
        .badge-danger { background: rgba(239, 68, 68, 0.15); color: #f87171; }
        .badge-info { background: rgba(6, 182, 212, 0.15); color: #22d3ee; }
        .badge-muted { background: rgba(148, 163, 184, 0.12); color: #cbd5f5; }

        .badge {
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            padding: 0.25rem 0.6rem;
            border-radius: 999px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.08em;
        }

        .badge.success { background: rgba(16, 185, 129, 0.15); color: #34d399; }
        .badge.warning { background: rgba(245, 158, 11, 0.15); color: #fbbf24; }
        .badge.danger { background: rgba(239, 68, 68, 0.15); color: #f87171; }
        .badge.info { background: rgba(6, 182, 212, 0.15); color: #22d3ee; }
        .badge.admin { background: rgba(68, 192, 255, 0.15); color: #7dd3fc; }
        .badge.operator { background: rgba(248, 113, 113, 0.15); color: #fca5a5; }
        .badge.viewer { background: rgba(148, 163, 184, 0.15); color: #cbd5f5; }

        /* Responsive */
        @media (max-width: 768px) {
            .sidebar {
                transform: translateX(-100%);
            }

            .sidebar.show {
                transform: translateX(0);
            }

            .main-wrapper {
                margin-left: 0;
            }

            .topbar {
                padding: 1rem;
            }

            .topbar-title {
                font-size: 1.25rem;
            }

            .topbar-right {
                gap: 1rem;
            }

            .content-area {
                padding: 1rem;
            }
        }

        /* Mobile Toggle Button */
        .mobile-toggle {
            display: none;
            background: none;
            border: none;
            color: var(--text-light);
            font-size: 1.5rem;
            cursor: pointer;
            padding: 0;
        }

        @media (max-width: 768px) {
            .mobile-toggle {
                display: flex;
            }
        }
    </style>

    @yield('styles')
</head>
<body>
    <!-- Sidebar -->
    <aside class="sidebar">
        <div class="sidebar-header">
            <a href="{{ route('admin.dashboard') }}" class="sidebar-brand">
                <i class="fas fa-chart-line"></i>
                <span>Quoodle</span>
            </a>
        </div>

        <ul class="nav-menu">
            <li class="nav-item">
                <a href="{{ route('admin.dashboard') }}" class="nav-link {{ request()->routeIs('admin.dashboard') ? 'active' : '' }}">
                    <i class="fas fa-home"></i>
                    <span>Dashboard</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.users') }}" class="nav-link {{ request()->routeIs('admin.users') ? 'active' : '' }}">
                    <i class="fas fa-users"></i>
                    <span>Users</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.devices') }}" class="nav-link {{ request()->routeIs('admin.devices') ? 'active' : '' }}">
                    <i class="fas fa-mobile-alt"></i>
                    <span>Fleet</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.commands') }}" class="nav-link {{ request()->routeIs('admin.commands') ? 'active' : '' }}">
                    <i class="fas fa-terminal"></i>
                    <span>Commands</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.compliance') }}" class="nav-link {{ request()->routeIs('admin.compliance') ? 'active' : '' }}">
                    <i class="fas fa-shield-alt"></i>
                    <span>Compliance</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.alerts') }}" class="nav-link {{ request()->routeIs('admin.alerts') ? 'active' : '' }}">
                    <i class="fas fa-bell"></i>
                    <span>Alerts</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.audit') }}" class="nav-link {{ request()->routeIs('admin.audit') ? 'active' : '' }}">
                    <i class="fas fa-history"></i>
                    <span>Audit Log</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.investigations') }}" class="nav-link {{ request()->routeIs('admin.investigations') ? 'active' : '' }}">
                    <i class="fas fa-magnifying-glass"></i>
                    <span>Investigations</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.policy') }}" class="nav-link {{ request()->routeIs('admin.policy') ? 'active' : '' }}">
                    <i class="fas fa-layer-group"></i>
                    <span>Policy</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.system') }}" class="nav-link {{ request()->routeIs('admin.system') ? 'active' : '' }}">
                    <i class="fas fa-server"></i>
                    <span>System Status</span>
                </a>
            </li>
        </ul>
    </aside>

    <!-- Main Content Wrapper -->
    <div class="main-wrapper">
        <!-- Top Bar -->
        <div class="topbar">
            <div style="display: flex; align-items: center; gap: 1rem;">
                <button class="mobile-toggle" id="mobileToggle">
                    <i class="fas fa-bars"></i>
                </button>
                <h1 class="topbar-title">@yield('title', 'Dashboard')</h1>
            </div>

            <div class="topbar-right">
                <div class="user-info">
                    <i class="fas fa-user-circle" style="font-size: 1.5rem; color: var(--accent-blue);"></i>
                    <div>
                        <div class="user-name">{{ auth()->user()->display_name ?? auth()->user()->name ?? 'Admin' }}</div>
                        <div style="font-size: 0.75rem; color: var(--text-muted);">
                            Role: {{ ucfirst(auth()->user()->role ?? 'admin') }}
                        </div>
                    </div>
                </div>
                <form method="POST" action="{{ route('logout') }}" style="margin: 0;">
                    @csrf
                    <button type="submit" class="logout-btn">
                        <i class="fas fa-sign-out-alt"></i> Logout
                    </button>
                </form>
            </div>
        </div>

        <!-- Content Area -->
        <div class="content-area">
            @yield('content')
        </div>
    </div>

    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>

    <!-- Mobile Sidebar Toggle -->
    <script>
        document.getElementById('mobileToggle').addEventListener('click', function() {
            document.querySelector('.sidebar').classList.toggle('show');
        });

        // Close sidebar when clicking outside
        document.addEventListener('click', function(event) {
            const sidebar = document.querySelector('.sidebar');
            const toggle = document.getElementById('mobileToggle');
            if (!sidebar.contains(event.target) && !toggle.contains(event.target)) {
                sidebar.classList.remove('show');
            }
        });
    </script>

    @yield('scripts')
</body>
</html>
