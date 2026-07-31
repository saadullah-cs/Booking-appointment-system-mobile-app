import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../shared/widgets/app_shell_scaffold.dart';
import '../../shared/widgets/premium_card.dart';
import '../../../services/staff_activity_logger.dart';
import '../../../theme/app_theme.dart';
import '../auth_providers.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  bool _allowStaffView = true;
  bool _allowStaffPaymentQuickView = false;
  List<Map<String, String>> _staffList = [];
  bool _isLoading = true;
  String _previewTab = 'login';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final authRepo = ref.read(authRepositoryProvider);
    final toggle = await authRepo.getStaffViewToggle();
    final paymentToggle = await authRepo.getStaffPaymentQuickViewToggle();
    final list = await authRepo.loadStaffCredentials();
    if (!mounted) return;
    setState(() {
      _allowStaffView = toggle;
      _allowStaffPaymentQuickView = paymentToggle;
      _staffList = list;
      _isLoading = false;
    });
  }

  Future<void> _toggleAccess(bool value) async {
    setState(() => _allowStaffView = value);
    await ref.read(authRepositoryProvider).setStaffViewToggle(value);
    _showSnackBar(
      value
          ? 'Staff access enabled. Appointments can be viewed online.'
          : 'Staff access disabled. Appointments hidden.',
    );
  }

  Future<void> _togglePaymentQuickViewAccess(bool value) async {
    setState(() => _allowStaffPaymentQuickView = value);
    await ref.read(authRepositoryProvider).setStaffPaymentQuickViewToggle(value);
    _showSnackBar(
      value
          ? 'Staff Payment Quick View enabled. Revenue summary visible to staff.'
          : 'Staff Payment Quick View disabled. Revenue summary hidden from staff.',
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addOrEditStaff({Map<String, String>? existingStaff}) async {
    final isEdit = existingStaff != null;
    final emailController = TextEditingController(
      text: existingStaff?['email'] ?? '',
    );
    final passwordController = TextEditingController(
      text: existingStaff?['password'] ?? '',
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            isEdit ? 'Edit Staff Credentials' : 'Add Staff Member',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isEdit) ...[
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Staff Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'receptionist@gct.com',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!val.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Text(
                    'Editing: ${existingStaff['email']}',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                    hintText: 'Enter secure password',
                  ),
                  obscureText: true,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Password is required';
                    }
                    if (val.trim().length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(ctx);

                final email = emailController.text.trim();
                final password = passwordController.text.trim();

                setState(() => _isLoading = true);
                try {
                  await ref
                      .read(authRepositoryProvider)
                      .addStaffCredential(email, password);
                  _showSnackBar(
                    isEdit
                        ? 'Staff credentials updated.'
                        : 'Staff member added successfully!',
                  );
                  await _loadData();
                } catch (e) {
                  _showSnackBar('Operation failed: $e', isError: true);
                  setState(() => _isLoading = false);
                }
              },
              child: Text(isEdit ? 'Save Changes' : 'Create Account'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteStaff(String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Staff Account',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete credentials for $email? They will no longer be able to log in.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).deleteStaffCredential(email);
      _showSnackBar('Staff account deleted.');
      await _loadData();
    } catch (e) {
      _showSnackBar('Delete failed: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearStaffLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Clear Staff Audit Logs',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to permanently clear all staff activity audit logs?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Clear All Logs',
              style: GoogleFonts.poppins(
                color: Theme.of(ctx).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await StaffActivityLogger().clearAllLogs();
      _showSnackBar('All staff activity logs cleared successfully.');
    } catch (e) {
      _showSnackBar('Failed to clear logs: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width > 900;

    // Helper widget for settings panel content
    Widget buildSettingsPanel() {
      return ListView(
        shrinkWrap: isWide,
        physics: isWide ? const ClampingScrollPhysics() : null,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Top Intro Card
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.people_alt_rounded,
                    color: cs.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Staff Portal Control',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'Manage staff credentials and toggle appointments access for the separate Staff App.',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Access Switch
          Text(
            'APPOINTMENTS ACCESS STATUS',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          PremiumCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SwitchListTile.adaptive(
              value: _allowStaffView,
              onChanged: _toggleAccess,
              title: Text(
                'Allow Staff to View Bookings',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                'Enable or disable appointment listing on the Staff App.',
                style: GoogleFonts.poppins(fontSize: 12),
              ),
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_allowStaffView ? cs.primary : Colors.grey)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _allowStaffView
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: _allowStaffView ? cs.primary : Colors.grey,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          PremiumCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SwitchListTile.adaptive(
              value: _allowStaffPaymentQuickView,
              onChanged: _togglePaymentQuickViewAccess,
              title: Text(
                'Show Payment Quick View to Staff',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                'Enable or disable revenue & payment metrics on Staff Dashboard.',
                style: GoogleFonts.poppins(fontSize: 12),
              ),
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_allowStaffPaymentQuickView ? cs.primary : Colors.grey)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _allowStaffPaymentQuickView
                      ? Icons.payments_rounded
                      : Icons.payments_outlined,
                  color: _allowStaffPaymentQuickView ? cs.primary : Colors.grey,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Credentials Management list header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STAFF LOGIN ACCOUNTS',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 0.5,
                ),
              ),
              TextButton.icon(
                onPressed: () => _addOrEditStaff(),
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Add Account',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Staff accounts list
          if (_staffList.isEmpty)
            PremiumCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 40,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Staff Accounts Added',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add staff logins so they can access the appointment reminders on their devices.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            PremiumCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _staffList.length,
                separatorBuilder: (ctx, i) =>
                    const Divider(indent: 16, endIndent: 16),
                itemBuilder: (ctx, index) {
                  final staff = _staffList[index];
                  final email = staff['email'] ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.primary.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: cs.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      email,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Access: Appointments only',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                          ),
                          tooltip: 'Clinic Chat',
                          onPressed: () => context.push('/chat'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit Password',
                          onPressed: () =>
                              _addOrEditStaff(existingStaff: staff),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: cs.error,
                          ),
                          tooltip: 'Delete Account',
                          onPressed: () => _deleteStaff(email),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STAFF ACTIVITY AUDIT LOGS',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 0.5,
                ),
              ),
              TextButton.icon(
                onPressed: _clearStaffLogs,
                icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                label: Text(
                  'Clear Logs',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.error,
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: cs.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<StaffActivityLog>>(
            stream: StaffActivityLogger().streamLogs(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return PremiumCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: cs.onSurface.withValues(alpha: 0.4), size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'No staff audit activity recorded yet.',
                        style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                );
              }
              final logs = snapshot.data!.take(10).toList();
              return PremiumCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: logs.map((log) {
                    final timeStr = DateFormat('MMM d, HH:mm:ss').format(log.timestamp);
                    final isLogin = log.action.toLowerCase().contains('login');
                    final isLogout = log.action.toLowerCase().contains('logout');
                    final color = isLogin ? Colors.green : (isLogout ? Colors.orange : cs.primary);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isLogin ? Icons.login_rounded : (isLogout ? Icons.logout_rounded : Icons.touch_app_rounded),
                              color: color,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${log.staffEmail} — ${log.action}',
                                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
                                ),
                                Text(
                                  '${log.featureUsed} • $timeStr',
                                  style: GoogleFonts.poppins(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              log.action.toUpperCase(),
                              style: GoogleFonts.poppins(fontSize: 8.5, fontWeight: FontWeight.w700, color: color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),

          if (!isWide) ...[
            const SizedBox(height: 24),
            Text(
              'STAFF APP LIVE PREVIEW',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            PremiumCard(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Text(
                    'Interactive Live Preview',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Simulate how staff members will see the portal on their devices in real-time.',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: StaffAppPreviewMock(
                      allowStaffView: _allowStaffView,
                      activeTab: _previewTab,
                      onTabChanged: (tab) => setState(() => _previewTab = tab),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    return AppShellScaffold(
      title: 'Staff Portal Settings',
      currentRoute: '/profile',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Control settings panel
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: buildSettingsPanel()),
                ),
                // Vertical Separator
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.onSurface.withValues(alpha: 0.08),
                ),
                // Right Column: Interactive Live Preview mockup
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Interactive Live Preview',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select a tab inside the mockup below to test screen states. Disabling view access will instantly lock the dashboard screen in real-time.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: StaffAppPreviewMock(
                            allowStaffView: _allowStaffView,
                            activeTab: _previewTab,
                            onTabChanged: (tab) =>
                                setState(() => _previewTab = tab),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : buildSettingsPanel(),
    );
  }
}

class StaffAppPreviewMock extends StatelessWidget {
  final bool allowStaffView;
  final String activeTab; // 'login', 'dashboard', 'suspended'
  final Function(String) onTabChanged;

  const StaffAppPreviewMock({
    super.key,
    required this.allowStaffView,
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Outer phone shell
    return Container(
      width: 280,
      height: 520,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.2),
          width: 8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Phone status bar & notch
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '9:41',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                // Notch
                Container(
                  width: 50,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.2),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                  ),
                ),
                Icon(
                  Icons.signal_cellular_4_bar_rounded,
                  size: 10,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ],
            ),
          ),

          // Main phone screen content
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: isDark
                    ? const Color(0xFF070F1C)
                    : const Color(0xFFF8FAFC),
                child: _buildScreenContent(context),
              ),
            ),
          ),

          // Bottom navigation bar mock / tab selector for the preview
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMockTabButton(
                  Icons.lock_rounded,
                  'Login',
                  'login',
                  isDark,
                  cs,
                ),
                _buildMockTabButton(
                  Icons.security_rounded,
                  'PIN Lock',
                  'lock',
                  isDark,
                  cs,
                ),
                _buildMockTabButton(
                  Icons.dashboard_rounded,
                  'Dashboard',
                  'dashboard',
                  isDark,
                  cs,
                ),
                _buildMockTabButton(
                  Icons.gpp_maybe_rounded,
                  'Suspended',
                  'suspended',
                  isDark,
                  cs,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockTabButton(
    IconData icon,
    String label,
    String tab,
    bool isDark,
    ColorScheme cs,
  ) {
    final isSelected = activeTab == tab;
    return GestureDetector(
      onTap: () => onTabChanged(tab),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected
                ? cs.primary
                : (isDark ? Colors.white38 : Colors.black38),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 8,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? cs.primary
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenContent(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Handle security override preview state automatically or manually
    final effectiveTab = !allowStaffView ? 'suspended' : activeTab;

    switch (effectiveTab) {
      case 'suspended':
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.gpp_maybe_rounded,
                size: 48,
                color: Colors.amber,
              ),
              const SizedBox(height: 12),
              Text(
                'Access Suspended',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'The Clinic Administrator has currently disabled staff-side appointment views.',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                width: 100,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Exit Portal',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );

      case 'lock':
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.primary, width: 2),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.badge_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'RECEPTIONIST',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Enter 4-Digit PIN to unlock',
                style: GoogleFonts.poppins(fontSize: 8, color: Colors.white70),
              ),
              const SizedBox(height: 18),
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < 2; // Mock 2 digits entered
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? cs.primary : Colors.transparent,
                      border: Border.all(color: cs.primary, width: 1.5),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              // Keypad mock
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        '1',
                        '2',
                        '3',
                      ].map((d) => _buildMockKey(d)).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        '4',
                        '5',
                        '6',
                      ].map((d) => _buildMockKey(d)).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        '7',
                        '8',
                        '9',
                      ].map((d) => _buildMockKey(d)).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const SizedBox(width: 32, height: 32),
                        _buildMockKey('0'),
                        const Icon(
                          Icons.backspace_outlined,
                          color: Colors.white70,
                          size: 14,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case 'dashboard':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mock AppBar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              color: cs.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Staff Dashboard',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'Signed in: receptionist@gct.com',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.forum_rounded, size: 14, color: cs.primary),
                      const SizedBox(width: 8),
                      Icon(Icons.sync_rounded, size: 14, color: cs.primary),
                    ],
                  ),
                ],
              ),
            ),

            // Mock Metrics (Redesigned Unified Card)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.analytics_rounded,
                          color: cs.primary,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Appointments Quick View',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildMockStatItemVertical(
                          'TODAY',
                          '3',
                          Icons.calendar_today_rounded,
                          cs.primary,
                          cs,
                        ),
                        _buildMockDivider(),
                        _buildMockStatItemVertical(
                          'PENDING',
                          '1',
                          Icons.hourglass_empty_rounded,
                          Colors.amber,
                          cs,
                        ),
                        _buildMockDivider(),
                        _buildMockStatItemVertical(
                          'CONFIRMED',
                          '2',
                          Icons.check_circle_outline_rounded,
                          Colors.green,
                          cs,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Mock Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 12,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Search patients...',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Mock Appointments List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  _buildMockAptTile(
                    'John Doe',
                    'Adjustments',
                    '10:00 AM',
                    'Confirmed',
                    cs,
                  ),
                  _buildMockAptTile(
                    'Sarah Smith',
                    'Spine Scan',
                    '11:30 AM',
                    'Pending',
                    cs,
                  ),
                  _buildMockAptTile(
                    'Bob Johnson',
                    'Initial Consult',
                    '02:00 PM',
                    'Confirmed',
                    cs,
                  ),
                ],
              ),
            ),
          ],
        );

      case 'login':
      default:
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo mock
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.badge_rounded, color: cs.primary, size: 24),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'GONSTEAD CLINIC',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                'STAFF ACCESS PORTAL',
                style: GoogleFonts.poppins(
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Fields mock
              _buildMockTextField('Staff Email', 'receptionist@gct.com', cs),
              const SizedBox(height: 10),
              _buildMockTextField('Access Password', '••••••••', cs),
              const SizedBox(height: 20),

              // Button mock
              Container(
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sign In as Staff',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildMockKey(String label) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildMockDivider() {
    return Container(height: 20, width: 1, color: Colors.grey.withValues(alpha: 0.2));
  }

  Widget _buildMockStatItemVertical(
    String label,
    String value,
    IconData icon,
    Color color,
    ColorScheme cs,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 6,
            fontWeight: FontWeight.bold,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildMockAptTile(
    String name,
    String type,
    String time,
    String status,
    ColorScheme cs,
  ) {
    final statusColor = status == 'Confirmed' ? Colors.green : Colors.amber;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              Text(
                '$type • $time',
                style: GoogleFonts.poppins(
                  fontSize: 8,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status,
              style: GoogleFonts.poppins(
                fontSize: 6,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockTextField(String label, String value, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 6,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(fontSize: 9, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}
