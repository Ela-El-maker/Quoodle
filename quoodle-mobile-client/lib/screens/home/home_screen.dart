import 'package:flutter/material.dart';

import '../../utils/rbac.dart';
import '../audit/audit_ledger_screen.dart';
import '../commands/command_center_screen.dart';
import '../devices/device_list_screen.dart';
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
            .map((t) => BottomNavigationBarItem(icon: t.icon, label: t.label))
            .toList(),
      ),
    );
  }

  List<_TabItem> _tabs() {
    final role = Rbac.currentRole();
    final tabs = <_TabItem>[
      const _TabItem(
        icon: Icon(Icons.devices),
        label: 'Fleet',
        screen: DeviceListScreen(),
      ),
      if (Rbac.hasAtLeast(UserRole.operator, role: role))
        const _TabItem(
          icon: Icon(Icons.bolt),
          label: 'Commands',
          screen: CommandCenterScreen(),
        ),
      const _TabItem(
        icon: Icon(Icons.shield),
        label: 'Audit',
        screen: AuditLedgerScreen(),
      ),
      const _TabItem(
        icon: Icon(Icons.settings),
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
    required this.label,
    required this.screen,
  });

  final Icon icon;
  final String label;
  final Widget screen;
}
