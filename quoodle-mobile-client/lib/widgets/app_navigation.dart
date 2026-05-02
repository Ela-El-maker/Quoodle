import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/notifications/presentation/providers/notification_providers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import '../theme/app_theme.dart';

class AppNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static final List<_NavItem> _items = [
    _NavItem(Icons.dashboard_rounded, Icons.dashboard_outlined, 'Fleet'),
    _NavItem(Icons.devices_rounded, Icons.devices_outlined, 'Devices'),
    _NavItem(Icons.terminal_rounded, Icons.terminal_outlined, 'Commands'),
    _NavItem(
      Icons.notifications_rounded,
      Icons.notifications_outlined,
      'Alerts',
    ),
    _NavItem(
      Icons.account_circle_rounded,
      Icons.account_circle_outlined,
      'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    if (isTablet) {
      return _TabletNavRail(currentIndex: currentIndex, onTap: onTap);
    }
    return _LiquidGlassBar(currentIndex: currentIndex, onTap: onTap);
  }
}

class _NavItem {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  _NavItem(this.activeIcon, this.inactiveIcon, this.label);
}

class _LiquidGlassBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  const _LiquidGlassBar({required this.currentIndex, required this.onTap});

  @override
  State<_LiquidGlassBar> createState() => _LiquidGlassBarState();
}

class _LiquidGlassBarState extends State<_LiquidGlassBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pillController;
  late Animation<double> _pillAnimation;
  int _prevIndex = 0;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.currentIndex;
    _pillController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _pillAnimation = CurvedAnimation(
      parent: _pillController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(_LiquidGlassBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prevIndex = old.currentIndex;
      _pillController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = AppNavigation._items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final itemWidth = constraints.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _pillAnimation,
                      builder: (_, __) {
                        final from = _prevIndex * itemWidth + 6;
                        final to = widget.currentIndex * itemWidth + 6;
                        final left = from + (to - from) * _pillAnimation.value;
                        return Positioned(
                          left: left,
                          top: 6,
                          child: Container(
                            width: itemWidth - 12,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryDim,
                              borderRadius: BorderRadius.circular(10.0),
                              border: Border.all(
                                color: AppTheme.primary.withAlpha(80),
                                width: 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Row(
                      children: List.generate(items.length, (i) {
                        final isActive = i == widget.currentIndex;
                        final showBadge = i == 3;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => widget.onTap(i),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Icon(
                                        isActive
                                            ? items[i].activeIcon
                                            : items[i].inactiveIcon,
                                        key: ValueKey(isActive),
                                        size: 20,
                                        color: isActive
                                            ? AppTheme.primary
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                    if (showBadge)
                                      Positioned(
                                        top: -4,
                                        right: -6,
                                        child: _UnreadBadge(),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Text(
                                  items[i].label,
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 11,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isActive
                                        ? AppTheme.primary
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated unread badge that listens to PushNotificationService
class _UnreadBadge extends ConsumerWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider);
    if (count == 0) return const SizedBox.shrink();
    return Container(
      constraints: BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.critical,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: AppTheme.background, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TabletNavRail extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  const _TabletNavRail({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = AppNavigation._items;
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          right: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 20),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.shield_rounded,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          SizedBox(height: 32),
          ...List.generate(items.length, (i) {
            final isActive = i == currentIndex;
            final showBadge = i == 3;
            return GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.primaryDim : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isActive
                      ? Border.all(
                          color: AppTheme.primary.withAlpha(102),
                          width: 1,
                        )
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isActive ? items[i].activeIcon : items[i].inactiveIcon,
                      size: 22,
                      color: isActive ? AppTheme.primary : AppTheme.textMuted,
                    ),
                    if (showBadge)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: _UnreadBadge(),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Scaffold wrapper that handles bottom nav routing
class MainScaffold extends StatefulWidget {
  final int initialIndex;
  const MainScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onNavTap(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      AppNavigator.navigateToTab(
        context,
        index,
        profileTabTarget: ProfileTabTarget.settings,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const SizedBox.shrink(),
      extendBody: true,
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
