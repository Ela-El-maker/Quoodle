<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>@yield('title', 'Admin Dashboard') - Quoodle</title>

    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">

    <style>
        :root {
            --primary-dark: #0f172a;
            --secondary-dark: #1e293b;
            --card-dark: #1e293b;
            --border-dark: #334155;
            --text-light: #f1f5f9;
            --text-muted: #94a3b8;
            --accent-blue: #3b82f6;
            --accent-blue-dark: #1e40af;
            --success: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --info: #06b6d4;
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            background-color: var(--primary-dark);
            color: var(--text-light);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            overflow-x: hidden;
        }

        /* Sidebar Styles */
        .sidebar {
            position: fixed;
            top: 0;
            left: 0;
            width: 250px;
            height: 100vh;
            background-color: var(--secondary-dark);
            border-right: 1px solid var(--border-dark);
            overflow-y: auto;
            z-index: 1000;
            transition: transform 0.3s ease;
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
            background-color: var(--secondary-dark);
            border-bottom: 1px solid var(--border-dark);
            padding: 1rem 2rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
            position: sticky;
            top: 0;
            z-index: 500;
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
            background-color: rgba(59, 130, 246, 0.1);
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
                    <span>Devices</span>
                </a>
            </li>
            <li class="nav-item">
                <a href="{{ route('admin.commands') }}" class="nav-link {{ request()->routeIs('admin.commands') ? 'active' : '' }}">
                    <i class="fas fa-terminal"></i>
                    <span>Commands</span>
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
                    <span class="user-name">{{ auth()->user()->name ?? 'Admin' }}</span>
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
