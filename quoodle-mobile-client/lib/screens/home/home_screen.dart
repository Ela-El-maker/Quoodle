import 'package:flutter/material.dart';

import '../audit/audit_ledger_screen.dart';
import '../devices/device_list_screen.dart';
import 'dashboard_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const route = '/home';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final clampedIndex = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: clampedIndex,
        children: tabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: clampedIndex,
        onTap: (value) => setState(() => _index = value),
        items: tabs
            .map((t) => BottomNavigationBarItem(
                  icon: t.icon,
                  activeIcon: t.activeIcon,
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }

  List<_TabItem> _tabs() {
    final tabs = <_TabItem>[
      const _TabItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home_rounded),
        label: 'Home',
        screen: DashboardScreen(),
      ),
      const _TabItem(
        icon: Icon(Icons.devices_outlined),
        activeIcon: Icon(Icons.devices_rounded),
        label: 'Devices',
        screen: DeviceListScreen(),
      ),
      const _TabItem(
        icon: Icon(Icons.timeline_outlined),
        activeIcon: Icon(Icons.timeline_rounded),
        label: 'Activity',
        screen: AuditLedgerScreen(),
      ),
      const _TabItem(
        icon: Icon(Icons.settings_outlined),
        activeIcon: Icon(Icons.settings_rounded),
        label: 'Settings',
        screen: SettingsScreen(),
      ),
    ];
    return tabs;
  }
}

class _TabItem {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.screen,
  });

  final Icon icon;
  final Icon activeIcon;
  final String label;
  final Widget screen;
}
