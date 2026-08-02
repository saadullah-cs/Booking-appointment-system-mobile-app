import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../models/appointment.dart';
import '../../../services/app_preferences.dart';
import '../../../services/repository_providers.dart';
import '../../../theme/app_theme.dart';
import '../../auth/screens/security_lock_screen.dart';

class AppShellScaffold extends ConsumerStatefulWidget {
  const AppShellScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.floatingActionButton,
    this.useDrawer = true,
    this.currentRoute,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final bool useDrawer;
  final String? currentRoute;
  final Widget? bottomNavigationBar;

  @override
  ConsumerState<AppShellScaffold> createState() => _AppShellScaffoldState();
}

class _AppShellScaffoldState extends ConsumerState<AppShellScaffold>
    with WidgetsBindingObserver {
  static const _navRoutes = [
    '/dashboard',
    '/appointments',
    '/payments',
    '/notes',
    '/profile',
  ];

  // State variables
  static bool _isLockScreenShowing = false;
  static final List<String> _routeHistory = [];
  static DateTime? _lastBackClickTime;

  int get _navIndex {
    if (widget.currentRoute == null) return 0;
    final idx = _navRoutes.indexOf(widget.currentRoute!);
    return idx < 0 ? 0 : idx;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Add to history
    if (widget.currentRoute != null &&
        (_routeHistory.isEmpty || _routeHistory.last != widget.currentRoute)) {
      _routeHistory.add(widget.currentRoute!);
      if (_routeHistory.length > 20) {
        _routeHistory.removeAt(0);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AppPreferences.instance.prefs.then((prefs) {
        prefs.setBool('security_unlocked', false);
      });
    } else if (state == AppLifecycleState.resumed) {
      _checkPinLockOnResume();
    }
  }

  Future<void> _checkPinLockOnResume() async {
    if (_isLockScreenShowing) return;

    try {
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null) {
        try {
          await FirebaseAuth.instance.currentUser!.reload();
        } on FirebaseAuthException catch (e) {
          debugPrint(
            'Firebase session verification on resume failed (code: ${e.code})',
          );
          if (e.code == 'user-not-found' ||
              e.code == 'user-disabled' ||
              e.code == 'invalid-credential') {
            await FirebaseAuth.instance.signOut();
            final prefs = await AppPreferences.instance.prefs;
            await prefs.remove('local_auth_current_user');
            if (!mounted) return;
            context.go('/login');
            return;
          }
        }
      }
    } catch (_) {}

    final prefs = await AppPreferences.instance.prefs;
    final pinEnabled = prefs.getBool('security_pin_enabled') ?? false;
    final alreadyUnlocked = prefs.getBool('security_unlocked') ?? false;

    if (pinEnabled && !alreadyUnlocked) {
      _isLockScreenShowing = true;
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (context) => const SecurityLockScreen(),
          fullscreenDialog: true,
        ),
      );
      _isLockScreenShowing = false;
    }
  }

  List<Appointment> _filterUpcomingAppointments(
    List<Appointment> appointments, {
    required DateTime now,
  }) {
    return appointments.where((a) {
      final d = a.scheduledAt;
      final status = a.status.toLowerCase();
      // Logic Fix: Exclude completed, cancelled, and no-show from top notifications
      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'no show') {
        return false;
      }
      return d != null && d.isAfter(now) && d.difference(now).inHours < 24;
    }).toList();
  }

  void _showNotificationsSheet(BuildContext context, List<Appointment> list) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Notifications',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (list.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${list.length} new',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                SizedBox(
                  height: 150,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 40,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No upcoming appointments in the next 24 hours.',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final apt = list[index];
                      final diff = apt.scheduledAt!.difference(DateTime.now());
                      final hours = diff.inHours;
                      final minutes = diff.inMinutes % 60;
                      final timeStr = hours > 0
                          ? '$hours hr $minutes min'
                          : '$minutes min';

                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: Colors.orange,
                            ),
                          ),
                          title: Text(
                            apt.patientName,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${apt.treatmentType}  •  ${apt.time}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Upcoming in $timeStr',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/appointment/${apt.id}');
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final isNavRoute = _navRoutes.contains(widget.currentRoute);
    final isWide = MediaQuery.of(context).size.width > 850;
    final showPermanentDrawer = isWide && widget.useDrawer;

    // Riverpod synchronization for notifications
    final appointments = ref.watch(appointmentsProvider);
    final now = DateTime.now();
    final upcoming = _filterUpcomingAppointments(appointments, now: now);
    final upcomingCount = upcoming.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (canPop) {
          context.pop();
          return;
        }

        final nowTime = DateTime.now();

        if (_lastBackClickTime != null &&
            nowTime.difference(_lastBackClickTime!) <
                const Duration(milliseconds: 1500)) {
          _lastBackClickTime = null;
          if (widget.currentRoute != '/dashboard') {
            context.go('/dashboard');
            return;
          }
        }

        _lastBackClickTime = nowTime;

        if (_routeHistory.length > 1) {
          _routeHistory.removeLast();
          final previousRoute = _routeHistory.last;
          if (previousRoute != widget.currentRoute) {
            context.go(previousRoute);
            return;
          }
        }

        if (widget.currentRoute != '/dashboard') {
          context.go('/dashboard');
          return;
        }

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Exit App',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Are you sure you want to quit the app?',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Exit'),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => context.pop(),
                  tooltip: 'Back',
                )
              : (widget.useDrawer && !isWide)
              ? Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    tooltip: 'Open menu',
                  ),
                )
              : null,
          titleSpacing: 0,
          title: Row(
            children: [
              if (!canPop && !showPermanentDrawer) ...[
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
                  ),
                ),
              ],
              Expanded(
                child: Text(widget.title, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => _showNotificationsSheet(context, upcoming),
                  tooltip: 'Notifications',
                ),
                if (upcomingCount > 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            ...widget.actions,
          ],
        ),
        drawer: (widget.useDrawer && !isWide)
            ? _AppDrawer(currentRoute: widget.currentRoute)
            : null,
        body: SafeArea(
          child: showPermanentDrawer
              ? Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _AppDrawer(currentRoute: widget.currentRoute),
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: widget.body,
                        ),
                      ),
                    ),
                  ],
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: widget.body,
                  ),
                ),
        ),
        floatingActionButton: widget.floatingActionButton,
        bottomNavigationBar: (isNavRoute && !isWide)
            ? _AppBottomNav(
                currentIndex: _navIndex,
                onTap: (index) {
                  final route = _navRoutes[index];
                  if (route != widget.currentRoute) {
                    context.go(route);
                  }
                },
              )
            : (!isWide ? widget.bottomNavigationBar : null),
      ),
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      animationDuration: const Duration(milliseconds: 300),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note_rounded),
          label: 'Appts',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet_rounded),
          label: 'Payments',
        ),
        NavigationDestination(
          icon: Icon(Icons.book_outlined),
          selectedIcon: Icon(Icons.book_rounded),
          label: 'Notes',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({this.currentRoute});

  final String? currentRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.heroGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gonstead Clinic',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Patient Care System',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 11,
              itemBuilder: (context, index) {
                switch (index) {
                  case 0:
                    return _DrawerTile(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      selected: currentRoute == '/dashboard',
                      onTap: () => _navigate(context, '/dashboard'),
                    );
                  case 1:
                    return _DrawerTile(
                      icon: Icons.event_available_rounded,
                      label: 'Book Appointment',
                      selected: currentRoute == '/booking',
                      onTap: () => _navigate(context, '/booking'),
                    );
                  case 2:
                    return _DrawerTile(
                      icon: Icons.list_alt_rounded,
                      label: 'All Appointments',
                      selected: currentRoute == '/appointments',
                      onTap: () => _navigate(context, '/appointments'),
                    );
                  case 3:
                    return _DrawerTile(
                      icon: Icons.analytics_rounded,
                      label: 'Analytics',
                      selected: currentRoute == '/analytics',
                      onTap: () => _navigate(context, '/analytics'),
                    );
                  case 4:
                    return _DrawerTile(
                      icon: Icons.biotech_rounded,
                      label: 'AI Vision Analyzer',
                      selected: currentRoute == '/vision-analyzer',
                      onTap: () => _navigate(context, '/vision-analyzer'),
                    );
                  case 5:
                    return _DrawerTile(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Payments',
                      selected: currentRoute == '/payments',
                      onTap: () => _navigate(context, '/payments'),
                    );
                  case 6:
                    return _DrawerTile(
                      icon: Icons.calculate_rounded,
                      label: 'Calculator',
                      selected: currentRoute == '/calculator',
                      onTap: () => _navigate(context, '/calculator'),
                    );
                  case 7:
                    return _DrawerTile(
                      icon: Icons.book_rounded,
                      label: 'Clinical Notes',
                      selected: currentRoute == '/notes',
                      onTap: () => _navigate(context, '/notes'),
                    );
                  case 8:
                    return _DrawerTile(
                      icon: Icons.history_rounded,
                      label: 'Patient History',
                      selected: currentRoute == '/patient-history',
                      onTap: () => _navigate(context, '/patient-history'),
                    );
                  case 9:
                    return _DrawerTile(
                      icon: Icons.forum_rounded,
                      label: 'Clinic Chat',
                      selected: currentRoute == '/chat',
                      onTap: () => _navigate(context, '/chat'),
                    );
                  case 10:
                    return _DrawerTile(
                      icon: Icons.person_rounded,
                      label: 'Profile',
                      selected: currentRoute == '/profile',
                      onTap: () => _navigate(context, '/profile'),
                    );
                  default:
                    return const SizedBox.shrink();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    try {
      if (Scaffold.of(context).isDrawerOpen) {
        Navigator.of(context).pop();
      }
    } catch (_) {}
    if (currentRoute == route) return;
    context.go(route);
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        icon,
        color: selected
            ? colors.primary
            : colors.onSurface.withValues(alpha: 0.55),
        size: 22,
      ),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          fontSize: 14,
          color: selected
              ? colors.primary
              : colors.onSurface.withValues(alpha: 0.8),
        ),
      ),
      selected: selected,
      selectedTileColor: colors.primary.withValues(alpha: 0.1),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      minLeadingWidth: 24,
    );
  }
}
