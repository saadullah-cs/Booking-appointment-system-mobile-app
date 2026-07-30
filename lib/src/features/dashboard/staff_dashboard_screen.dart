import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/appointment.dart';
import '../../services/app_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/payment_gateway_service.dart';
import '../../theme/app_theme.dart';
import '../shared/widgets/premium_card.dart';

class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  ConsumerState<StaffDashboardScreen> createState() =>
      _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  String _staffEmail = '';
  String _searchQuery = '';
  String _selectedStatus = 'All';
  bool _remindersSynced = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadStaffInfo();
  }

  Future<void> _loadStaffInfo() async {
    final prefs = await AppPreferences.instance.prefs;
    setState(() {
      _staffEmail = prefs.getString('logged_in_staff_email') ?? 'Staff Member';
    });
  }

  Future<void> _logout() async {
    final prefs = await AppPreferences.instance.prefs;
    await prefs.remove('is_staff_logged_in');
    await prefs.remove('logged_in_staff_email');
    if (!mounted) return;
    context.go('/login');
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _makeCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnackBar('Could not initiate call to $phoneNumber', isError: true);
    }
  }

  Future<void> _manualSync(List<Appointment> appointments) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await NotificationService().syncScheduledNotifications(appointments);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully synchronized speech reminders for ${appointments.length} appointments! ⏰',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync reminders: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _retryPayment(Appointment apt) async {
    final payService = PaymentGatewayService();
    try {
      final res = await payService.initializeSafepayTransaction(
        amount: apt.amount,
        currency: 'PKR',
        customerEmail: apt.email,
      );

      if (payService.safepayKey.isEmpty ||
          payService.safepayKey.contains('your_safepay_api_key')) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Payment Gateway - Test Mode'),
              content: const Text(
                'The online payment gateway is currently in Test Mode (Key unconfigured in .env). '
                'In production, this would launch the secure Safepay/PayFast checkout screen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Continue with Simulation'),
                ),
              ],
            ),
          );
        }
      } else {
        final url = Uri.parse(res['checkoutUrl'] ?? '');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint('Retry Payment failed: $e');
      _showSnackBar('Payment initialization failed: $e', isError: true);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildGreetingBanner(ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting,',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        Text(
          'Staff Member',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildGreetingCard(ThemeData theme, ColorScheme cs) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primary.withValues(alpha: 0.1),
                radius: 22,
                child: Icon(Icons.badge_rounded, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_greeting,',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    Text(
                      'Staff Member',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Signed in as:',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Text(
            _staffEmail,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildClinicInfoCard(ThemeData theme, ColorScheme cs) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clinic Info',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildMiniInfoRow(
            Icons.location_on_rounded,
            'Sector G-8/4, Islamabad',
            cs,
          ),
          const SizedBox(height: 8),
          _buildMiniInfoRow(Icons.phone_rounded, '+92 300 1234567', cs),
          const SizedBox(height: 8),
          _buildMiniInfoRow(
            Icons.access_time_filled_rounded,
            '9:00 AM - 6:00 PM',
            cs,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfoRow(IconData icon, String text, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildChatShortcutCard(ThemeData theme, ColorScheme cs) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Clinic Chat',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Need to coordinate or send a message to the clinic doctor?',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/chat'),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: Text(
                'Open Group Chat',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisionAnalyzerCard(ThemeData theme, ColorScheme cs) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'AI Patient Analyzer',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Analyze patient posture, gait mechanics, facial paralysis, or skin lesions using live camera scan or photo uploads.',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/vision-analyzer'),
              icon: const Icon(Icons.document_scanner_rounded, size: 16),
              label: Text(
                'Open Vision Analyzer',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailsBottomSheet(Appointment apt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final formattedDate = apt.scheduledAt != null
            ? DateFormat(
                'EEEE, MMMM dd, yyyy',
              ).format(apt.scheduledAt!.toLocal())
            : 'Unscheduled';
        final formattedTime = apt.scheduledAt != null
            ? DateFormat('hh:mm a').format(apt.scheduledAt!.toLocal())
            : apt.time;
        final cs = Theme.of(context).colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bottom sheet handle
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      apt.patientName,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusBgColor(apt.status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      apt.status.toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: statusColor(apt.status),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Treatment: ${apt.treatmentType}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              const Divider(height: 32),

              // Info grid
              _buildDetailItem(
                Icons.calendar_month_outlined,
                'Scheduled Date',
                formattedDate,
              ),
              const SizedBox(height: 16),
              _buildDetailItem(
                Icons.access_time_rounded,
                'Appointment Time',
                formattedTime,
              ),
              const SizedBox(height: 16),
              _buildDetailItem(
                Icons.phone_iphone_rounded,
                'Contact Phone',
                apt.phoneNumber,
              ),
              if (apt.patientNote.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildDetailItem(
                  Icons.notes_rounded,
                  'Additional Notes',
                  apt.patientNote,
                ),
              ],
              const Divider(height: 32),

              // Actions (Read-only call button)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _makeCall(apt.phoneNumber);
                      },
                      icon: const Icon(Icons.phone_rounded),
                      label: const Text('Call Patient'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Security assurance notice
              Center(
                child: Text(
                  '🔒 Staff member access is read-only.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: cs.primary.withValues(alpha: 0.8)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 36,
      width: 1,
      color: Colors.grey.withValues(alpha: 0.2),
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildStatItemVertical(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogKey(String label, void Function(String) onTap) {
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12, width: 1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<String?> _promptNewPin() async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String pin1 = '';
        String pin2 = '';
        bool isConfirming = false;
        String errorMessage = '';

        return StatefulBuilder(
          builder: (context, setStatePin) {
            final cs = Theme.of(context).colorScheme;

            void onKeyTap(String digit) {
              setStatePin(() {
                errorMessage = '';
                if (!isConfirming) {
                  if (pin1.length < 4) pin1 += digit;
                  if (pin1.length == 4) {
                    isConfirming = true;
                  }
                } else {
                  if (pin2.length < 4) pin2 += digit;
                  if (pin2.length == 4) {
                    if (pin1 == pin2) {
                      Navigator.pop(context, pin1);
                    } else {
                      errorMessage = 'PIN codes do not match!';
                      pin2 = '';
                    }
                  }
                }
              });
            }

            void onBackspace() {
              setStatePin(() {
                errorMessage = '';
                if (!isConfirming) {
                  if (pin1.isNotEmpty) {
                    pin1 = pin1.substring(0, pin1.length - 1);
                  }
                } else {
                  if (pin2.isNotEmpty) {
                    pin2 = pin2.substring(0, pin2.length - 1);
                  } else {
                    isConfirming = false;
                    pin1 = pin1.substring(0, pin1.length - 1);
                  }
                }
              });
            }

            final currentPinLength = isConfirming ? pin2.length : pin1.length;
            final titleText = isConfirming
                ? 'Confirm New PIN'
                : 'Enter New PIN';

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                titleText,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final filled = index < currentPinLength;
                      return Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? AppColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage,
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          '1',
                          '2',
                          '3',
                        ].map((d) => _buildDialogKey(d, onKeyTap)).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          '4',
                          '5',
                          '6',
                        ].map((d) => _buildDialogKey(d, onKeyTap)).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          '7',
                          '8',
                          '9',
                        ].map((d) => _buildDialogKey(d, onKeyTap)).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 50, height: 50),
                          _buildDialogKey('0', onKeyTap),
                          GestureDetector(
                            onTap: onBackspace,
                            child: Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.backspace_outlined,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _promptVerifyPin(String currentPin) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String pin = '';
        String errorMessage = '';

        return StatefulBuilder(
          builder: (context, setStatePin) {
            void onKeyTap(String digit) {
              setStatePin(() {
                errorMessage = '';
                if (pin.length < 4) pin += digit;
                if (pin.length == 4) {
                  if (pin == currentPin) {
                    Navigator.pop(context, true);
                  } else {
                    errorMessage = 'Incorrect PIN code!';
                    pin = '';
                  }
                }
              });
            }

            void onBackspace() {
              setStatePin(() {
                errorMessage = '';
                if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                'Enter Current PIN',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final filled = index < pin.length;
                      return Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? AppColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage,
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          '1',
                          '2',
                          '3',
                        ].map((d) => _buildDialogKey(d, onKeyTap)).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          '4',
                          '5',
                          '6',
                        ].map((d) => _buildDialogKey(d, onKeyTap)).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          '7',
                          '8',
                          '9',
                        ].map((d) => _buildDialogKey(d, onKeyTap)).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 50, height: 50),
                          _buildDialogKey('0', onKeyTap),
                          GestureDetector(
                            onTap: onBackspace,
                            child: Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.backspace_outlined,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(color: Colors.white70),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  Future<void> _openSecuritySettings() async {
    final prefs = await AppPreferences.instance.prefs;
    final email = _staffEmail;
    bool isEnabled = prefs.getBool('staff_pin_enabled_$email') ?? false;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final cs = Theme.of(context).colorScheme;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.security_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Security PIN Settings',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Secure your staff portal access with a 4-digit PIN lock on app launch and login.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(
                      'Require PIN Code',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: isEnabled,
                    activeThumbColor: cs.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) async {
                      if (val) {
                        final newPin = await _promptNewPin();
                        if (newPin != null) {
                          await prefs.setBool('staff_pin_enabled_$email', true);
                          await prefs.setString(
                            'staff_pin_code_$email',
                            newPin,
                          );
                          setStateDialog(() {
                            isEnabled = true;
                          });
                          _showSnackBar('PIN Code enabled successfully! 🎉');
                        }
                      } else {
                        final currentPin =
                            prefs.getString('staff_pin_code_$email') ?? '';
                        final verified = await _promptVerifyPin(currentPin);
                        if (verified) {
                          await prefs.setBool(
                            'staff_pin_enabled_$email',
                            false,
                          );
                          await prefs.remove('staff_pin_code_$email');
                          setStateDialog(() {
                            isEnabled = false;
                          });
                          _showSnackBar('PIN Code disabled.');
                        }
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_staffEmail.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 1. Listen to clinic staff view permissions & login validation in real-time
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('clinic_config')
          .snapshots(),
      builder: (context, configSnapshot) {
        if (configSnapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Error loading configuration: ${configSnapshot.error}',
              ),
            ),
          );
        }
        if (configSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final configData = configSnapshot.data?.data() as Map<String, dynamic>?;
        final allowStaffView = configData?['allowStaffView'] ?? false;

        // If clinic administrator disables the access toggle, suspend dashboard immediately
        if (!allowStaffView) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.gpp_maybe_rounded,
                      size: 80,
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Access Suspended',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The Clinic Administrator has currently disabled staff-side appointment views. Please contact your administrator.',
                      style: GoogleFonts.poppins(
                        color: Colors.grey,
                        fontSize: 13.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Exit Portal'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 2. Validate that staff email account still exists and password matches
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('staff')
              .doc(_staffEmail)
              .snapshots(),
          builder: (context, staffSnapshot) {
            if (staffSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'Error verifying credentials: ${staffSnapshot.error}',
                  ),
                ),
              );
            }
            if (staffSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final staffData =
                staffSnapshot.data?.data() as Map<String, dynamic>?;

            // If account is deleted or password changes, trigger automatic force logout
            if (staffData == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _logout();
                _showSnackBar(
                  'Your staff account has been deleted by the administrator.',
                  isError: true,
                );
              });
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // 3. Load all appointments in real-time
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('appointments')
                  .snapshots(),
              builder: (context, apptSnapshot) {
                if (apptSnapshot.hasError) {
                  return Scaffold(
                    body: Center(
                      child: Text(
                        'Error loading appointments: ${apptSnapshot.error}',
                      ),
                    ),
                  );
                }
                if (apptSnapshot.connectionState == ConnectionState.waiting) {
                  return Scaffold(
                    appBar: AppBar(), // Empty appbar to prevent visual glitch
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }

                // Map appointments to list
                final rawDocs = apptSnapshot.data?.docs ?? [];
                final appointments = rawDocs.map((doc) {
                  return Appointment.fromJson({
                    ...doc.data() as Map<String, dynamic>,
                    'id': doc.id,
                  });
                }).toList();

                // Sort descending scheduledAt
                appointments.sort((a, b) {
                  if (a.scheduledAt == null && b.scheduledAt == null) return 0;
                  if (a.scheduledAt == null) return 1;
                  if (b.scheduledAt == null) return -1;
                  return b.scheduledAt!.compareTo(a.scheduledAt!);
                });

                // Auto-sync reminders when data loads for the first time
                if (!_remindersSynced && appointments.isNotEmpty) {
                  _remindersSynced = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    NotificationService().syncScheduledNotifications(
                      appointments,
                    );
                  });
                }

                // Compute metrics
                final now = DateTime.now();
                final todayStr = DateFormat('yyyy-MM-dd').format(now);
                final todayCount = appointments.where((a) {
                  if (a.scheduledAt == null) return false;
                  return DateFormat(
                        'yyyy-MM-dd',
                      ).format(a.scheduledAt!.toLocal()) ==
                      todayStr;
                }).length;

                final pendingCount = appointments
                    .where((a) => a.status.toLowerCase() == 'pending')
                    .length;
                final confirmedCount = appointments
                    .where((a) => a.status.toLowerCase() == 'confirmed')
                    .length;

                // Compute revenue metrics
                final totalRevenue = appointments.fold<double>(
                  0,
                  (sum, a) => sum + a.amount,
                );
                final collectedRevenue = appointments
                    .where((a) => a.paymentStatus.toLowerCase() == 'paid')
                    .fold<double>(0, (sum, a) => sum + a.amount);
                final pendingRevenue = appointments
                    .where((a) => a.paymentStatus.toLowerCase() == 'pending')
                    .fold<double>(0, (sum, a) => sum + a.amount);

                // Apply search & status filter
                final filteredAppointments = appointments.where((apt) {
                  final matchesSearch =
                      apt.patientName.toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ) ||
                      apt.phoneNumber.contains(_searchQuery);
                  final matchesStatus =
                      _selectedStatus == 'All' ||
                      apt.status.toLowerCase() == _selectedStatus.toLowerCase();
                  return matchesSearch && matchesStatus;
                }).toList();

                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isWide = MediaQuery.of(context).size.width > 720;

                return Scaffold(
                  appBar: AppBar(
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff Dashboard',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          'Signed in: $_staffEmail',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // Clinic Chat Group
                      IconButton(
                        onPressed: () => context.push('/chat'),
                        icon: const Icon(Icons.forum_rounded),
                        tooltip: 'Clinic Chat',
                      ),
                      // Manual background speaking reminders sync button
                      IconButton(
                        onPressed: _isSyncing
                            ? null
                            : () => _manualSync(appointments),
                        icon: _isSyncing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              )
                            : const Icon(Icons.sync_rounded),
                        tooltip: 'Synchronize Reminders',
                      ),
                      IconButton(
                        onPressed: _openSecuritySettings,
                        icon: const Icon(Icons.security_rounded),
                        tooltip: 'Security Settings',
                      ),
                      IconButton(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded),
                        tooltip: 'Logout',
                      ),
                    ],
                  ),
                  body: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column (flex: 2)
                            Expanded(
                              flex: 2,
                              child: Column(
                                children: [
                                  _buildMetricsRow(
                                    todayCount,
                                    pendingCount,
                                    confirmedCount,
                                    totalRevenue,
                                    collectedRevenue,
                                    pendingRevenue,
                                  ),
                                  _buildSearchAndFilters(),
                                  Expanded(
                                    child: _buildAppointmentsList(
                                      filteredAppointments,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Vertical Divider
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: cs.onSurface.withValues(alpha: 0.08),
                            ),
                            // Right Column (flex: 1)
                            Expanded(
                              flex: 1,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildGreetingCard(theme, cs),
                                    const SizedBox(height: 16),
                                    _buildClinicInfoCard(theme, cs),
                                    const SizedBox(height: 16),
                                    _buildChatShortcutCard(theme, cs),
                                    const SizedBox(height: 16),
                                    _buildVisionAnalyzerCard(theme, cs),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const BouncingScrollPhysics(),
                          children: [
                            // Greeting banner on mobile
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: _buildGreetingBanner(theme, cs),
                            ),
                            _buildMetricsRow(
                              todayCount,
                              pendingCount,
                              confirmedCount,
                              totalRevenue,
                              collectedRevenue,
                              pendingRevenue,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: _buildVisionAnalyzerCard(theme, cs),
                            ),
                            _buildSearchAndFilters(),
                            _buildAppointmentsList(
                              filteredAppointments,
                              shrinkWrap: true,
                            ),
                          ],
                        ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMetricsRow(
    int todayCount,
    int pendingCount,
    int confirmedCount,
    double totalRevenue,
    double collectedRevenue,
    double pendingRevenue,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Appointments Quick View',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatItemVertical(
                      'TODAY',
                      todayCount.toString(),
                      Icons.calendar_today_rounded,
                      cs.primary,
                    ),
                    _buildDivider(),
                    _buildStatItemVertical(
                      'PENDING',
                      pendingCount.toString(),
                      Icons.hourglass_empty_rounded,
                      AppColors.statusPending,
                    ),
                    _buildDivider(),
                    _buildStatItemVertical(
                      'CONFIRMED',
                      confirmedCount.toString(),
                      Icons.check_circle_outline_rounded,
                      AppColors.statusConfirmed,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Payments Quick View',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatItemVertical(
                      'TOTAL',
                      'Rs. ${totalRevenue.toStringAsFixed(0)}',
                      Icons.account_balance_wallet_rounded,
                      cs.primary,
                    ),
                    _buildDivider(),
                    _buildStatItemVertical(
                      'COLLECTED',
                      'Rs. ${collectedRevenue.toStringAsFixed(0)}',
                      Icons.check_circle_rounded,
                      Colors.green,
                    ),
                    _buildDivider(),
                    _buildStatItemVertical(
                      'PENDING',
                      'Rs. ${pendingRevenue.toStringAsFixed(0)}',
                      Icons.pending_actions_rounded,
                      Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Search Field
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search patient name or phone...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  ['All', 'Pending', 'Confirmed', 'Completed', 'Cancelled'].map(
                    (status) {
                      final isSelected =
                          _selectedStatus.toLowerCase() == status.toLowerCase();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(status),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            setState(() {
                              _selectedStatus = selected ? status : 'All';
                            });
                          },
                          selectedColor: cs.primary.withValues(alpha: 0.15),
                          checkmarkColor: cs.primary,
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      );
                    },
                  ).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsList(
    List<Appointment> appointments, {
    bool shrinkWrap = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (appointments.isEmpty) {
      final placeholder = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 64,
              color: cs.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No appointments found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try checking spelling or changing filters'
                  : 'Appointments will appear here once booked',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
      return shrinkWrap
          ? placeholder
          : Center(child: SingleChildScrollView(child: placeholder));
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 4, 16, shrinkWrap ? 24 : 80),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final apt = appointments[index];
        final timeStr = apt.scheduledAt != null
            ? DateFormat('hh:mm a').format(apt.scheduledAt!.toLocal())
            : apt.time;
        final dateStr = apt.scheduledAt != null
            ? DateFormat('EEE, MMM d').format(apt.scheduledAt!.toLocal())
            : 'Unscheduled';
        final isEmergency = apt.isEmergency;

        final statusCol = statusColor(apt.status);
        final statusBg = statusBgColor(apt.status);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: PremiumCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => _showDetailsBottomSheet(apt),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Time and Date column
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            timeStr,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Patient name and Treatment type
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  apt.patientName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isEmergency) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusCancelledBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'EMERGENCY',
                                    style: GoogleFonts.poppins(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.statusCancelled,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            apt.treatmentType,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              // Payment Status Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: apt.paymentStatus == 'paid'
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: apt.paymentStatus == 'paid'
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : Colors.orange.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      apt.paymentStatus == 'paid'
                                          ? Icons.check_circle_rounded
                                          : Icons.info_rounded,
                                      size: 10,
                                      color: apt.paymentStatus == 'paid'
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      apt.paymentStatus == 'paid'
                                          ? 'PAID (Online)'
                                          : 'UNPAID (Pay at Clinic)',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: apt.paymentStatus == 'paid'
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (apt.paymentMethod == 'online' &&
                                  apt.paymentStatus == 'pending') ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => _retryPayment(apt),
                                  icon: const Icon(
                                    Icons.payment_rounded,
                                    size: 12,
                                  ),
                                  label: const Text('Pay Now'),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.blueAccent
                                        .withValues(alpha: 0.1),
                                    foregroundColor: Colors.blueAccent,
                                    textStyle: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 0,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Status Badge & Action button
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            apt.status,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusCol,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.phone_rounded,
                                color: cs.primary,
                                size: 18,
                              ),
                              onPressed: () => _makeCall(apt.phoneNumber),
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: cs.onSurface.withValues(alpha: 0.3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
