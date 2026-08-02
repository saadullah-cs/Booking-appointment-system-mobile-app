import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../utils/import_export_service.dart';
import '../../services/app_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:url_launcher/url_launcher_string.dart';

import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import '../../models/appointment.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repository_providers.dart';
import '../../services/payment_gateway_service.dart';
import '../../services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/visual_calendar_widget.dart';

class AppointmentsListScreen extends ConsumerStatefulWidget {
  const AppointmentsListScreen({super.key});

  @override
  ConsumerState<AppointmentsListScreen> createState() =>
      _AppointmentsListScreenState();
}

class _AppointmentsListScreenState extends ConsumerState<AppointmentsListScreen>
    with SingleTickerProviderStateMixin {
  final bool _isLoading = false;
  bool _isCalendarView = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDuration = 'All';
  String _selectedUrgency = 'All';
  String _selectedTreatmentType = 'All';
  bool _isFilterExpanded = false;

  List<Appointment> get _appointments => ref.read(appointmentsProvider);

  Future<void> _exportAppointments() async {
    try {
      final header = [
        'Appointment ID',
        'Patient Name',
        'Profession',
        'Scheduled Date & Time',
        'Treatment Type',
        'Phone Number',
        'Email',
        'Status',
        'Priority',
        'Reason for Visit',
        'Clinical Notes',
        'Cancellation Reason',
        'Last Updated',
      ];
      final rows = <List<dynamic>>[header];
      for (final apt in _appointments) {
        rows.add([
          apt.id,
          apt.patientName,
          apt.patientProfession,
          apt.scheduledAt != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(apt.scheduledAt!)
              : apt.time,
          apt.treatmentType,
          apt.phoneNumber,
          apt.email,
          apt.status,
          apt.isEmergency ? 'EMERGENCY' : 'Standard',
          apt.visitReason,
          apt.patientNote,
          apt.cancellationReason,
          apt.updatedAt != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(apt.updatedAt!)
              : '',
        ]);
      }

      final success = await ImportExportService.exportExcel(
        context: context,
        defaultFileName: 'gct_appointments.xlsx',
        sheets: {'Appointments': rows},
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointments exported to Excel successfully! 💾'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _importAppointments() async {
    try {
      final excel = await ImportExportService.importExcel(context: context);
      if (excel == null) return;

      final rows = ImportExportService.parseSheet(
        excel: excel,
        sheetName: 'Appointments',
      );
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No appointments sheet found or sheet is empty.'),
            ),
          );
        }
        return;
      }

      final List<Appointment> imported = [];
      for (final row in rows) {
        final id = row['Appointment ID']?.toString() ?? '';
        final patientName = row['Patient Name']?.toString() ?? '';
        final patientProfession = row['Profession']?.toString() ?? '';
        final scheduledRaw = row['Scheduled Date & Time']?.toString() ?? '';
        final treatmentType = row['Treatment Type']?.toString() ?? '';
        final phoneNumber = row['Phone Number']?.toString() ?? '';
        final email = row['Email']?.toString() ?? '';
        final status = row['Status']?.toString() ?? 'Pending';
        final priority = row['Priority']?.toString() ?? 'Standard';
        final visitReason = row['Reason for Visit']?.toString() ?? '';
        final patientNote = row['Clinical Notes']?.toString() ?? '';
        final cancellationReason = row['Cancellation Reason']?.toString() ?? '';
        final updatedRaw = row['Last Updated']?.toString() ?? '';

        DateTime? scheduledAt = DateTime.tryParse(scheduledRaw);
        DateTime? updatedAt = DateTime.tryParse(updatedRaw);

        if (patientName.isNotEmpty) {
          imported.add(
            Appointment(
              id: id.isNotEmpty ? id : Uuid().v4(),
              patientName: patientName,
              patientProfession: patientProfession,
              scheduledAt: scheduledAt,
              time: scheduledAt != null
                  ? DateFormat('hh:mm a').format(scheduledAt)
                  : scheduledRaw,
              treatmentType: treatmentType,
              phoneNumber: phoneNumber,
              email: email,
              status: status,
              isEmergency: priority == 'EMERGENCY',
              visitReason: visitReason,
              patientNote: patientNote,
              cancellationReason: cancellationReason,
              updatedAt: updatedAt,
            ),
          );
        }
      }

      final prefs = await AppPreferences.instance.prefs;
      await prefs.setString(
        'clinic_booked_appointments',
        jsonEncode(imported.map((item) => item.toJson()).toList()),
      );

      await ref.read(appointmentsProvider.notifier).load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointments imported successfully! 🔄'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: ${e.toString()}')),
        );
      }
    }
  }

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteAppointment(String id) async {
    // Delete via provider for real-time sync
    await ref.read(appointmentsProvider.notifier).delete(id);
    
    // Logic Fix: Cancel scheduled notifications on deletion
    try {
      await NotificationService().cancelAppointmentNotifications(id);
    } catch (e) {
      debugPrint('Failed to cancel notifications on delete: $e');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment initialization failed: $e')),
        );
      }
    }
  }

  bool _matchesDuration(DateTime? date) {
    if (_selectedDuration == 'All') return true;
    if (date == null) return false;
    final diff = DateTime.now().difference(date).abs();
    if (_selectedDuration == '7 Days') return diff.inDays <= 7;
    if (_selectedDuration == '30 Days') return diff.inDays <= 30;
    if (_selectedDuration == '6 Months') return diff.inDays <= 180;
    return true;
  }

  List<String> get _treatmentTypes {
    final types = _appointments
        .map((a) => a.treatmentType.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    types.sort();
    return ['All', ...types];
  }

  Widget _buildDurationFilterChips(ColorScheme cs) {
    final options = ['All', '7 Days', '30 Days', '6 Months'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final isSelected = _selectedDuration == opt;
          return GestureDetector(
            onTap: () => setState(() => _selectedDuration = opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? cs.primary
                      : cs.outline.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                opt,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUrgencyFilterChips(ColorScheme cs) {
    final urgencyOptions = ['All', 'Emergency', 'Standard'];
    return Row(
      children: urgencyOptions.map((opt) {
        final isSelected = _selectedUrgency == opt;
        return GestureDetector(
          onTap: () => setState(() => _selectedUrgency = opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? cs.primary
                    : cs.outline.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              opt,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTreatmentTypeFilterChips(ColorScheme cs) {
    final treatmentTypes = _treatmentTypes;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: treatmentTypes.map((opt) {
          final isSelected = _selectedTreatmentType == opt;
          return GestureDetector(
            onTap: () => setState(() => _selectedTreatmentType = opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? cs.secondary : cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? cs.secondary
                      : cs.outline.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                opt,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appointments = ref.watch(appointmentsProvider);
    
    // Internal filter logic using the watched state
    List<Appointment> filterByType(String type, List<Appointment> list) {
      final now = DateTime.now();
      List<Appointment> result;
      switch (type) {
        case 'upcoming':
          result = list.where((a) {
            final d = a.scheduledAt;
            return d != null &&
                d.isAfter(now) &&
                a.status.toLowerCase() != 'cancelled' &&
                a.status.toLowerCase() != 'completed';
          }).toList()..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
          break;
        case 'past':
          result = list.where((a) {
            final d = a.scheduledAt;
            return (d != null && d.isBefore(now)) ||
                a.status.toLowerCase() == 'completed';
          }).toList();
          break;
        case 'cancelled':
          result = list
              .where((a) => a.status.toLowerCase() == 'cancelled')
              .toList();
          break;
        default:
          result = list;
      }

      result = result.where((a) => _matchesDuration(a.scheduledAt)).toList();

      if (_selectedUrgency == 'Emergency') {
        result = result.where((a) => a.isEmergency).toList();
      } else if (_selectedUrgency == 'Standard') {
        result = result.where((a) => !a.isEmergency).toList();
      }

      if (_selectedTreatmentType != 'All') {
        result = result
            .where(
              (a) =>
                  a.treatmentType.toLowerCase() ==
                  _selectedTreatmentType.toLowerCase(),
            )
            .toList();
      }

      if (_searchQuery.isEmpty) return result;
      return result
          .where(
            (a) =>
                a.patientName.toLowerCase().contains(_searchQuery) ||
                a.treatmentType.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }

    final upcoming = filterByType('upcoming', appointments);
    final past = filterByType('past', appointments);
    final cancelled = filterByType('cancelled', appointments);

    return AppShellScaffold(
      title: 'All Appointments',
      currentRoute: '/appointments',
      actions: [
        IconButton(
          icon: Icon(
            _isCalendarView
                ? Icons.format_list_bulleted_rounded
                : Icons.calendar_month_rounded,
          ),
          onPressed: () => setState(() => _isCalendarView = !_isCalendarView),
          tooltip: _isCalendarView ? 'Switch to List View' : 'Switch to Calendar View',
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded),
          onPressed: _exportAppointments,
          tooltip: 'Export Appointments',
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_rounded),
          onPressed: _importAppointments,
          tooltip: 'Import Appointments',
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/booking'),
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          // Search & Filter Panel Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.poppins(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search by patient or treatment…',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        filled: true,
                        fillColor: cs.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: cs.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: cs.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: cs.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Toggle Filter Button
                Material(
                  color: _isFilterExpanded ? cs.primary : cs.surface,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap: () =>
                        setState(() => _isFilterExpanded = !_isFilterExpanded),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _isFilterExpanded
                              ? cs.primary
                              : cs.outline.withValues(alpha: 0.15),
                        ),
                        boxShadow: [
                          if (!_isFilterExpanded)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Icon(
                        Icons.filter_list_rounded,
                        color: _isFilterExpanded ? Colors.white : cs.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Animated Filter drawer
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Appointments',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.primary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDuration = 'All';
                            _selectedUrgency = 'All';
                            _selectedTreatmentType = 'All';
                          });
                        },
                        child: Text(
                          'Reset',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Duration',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildDurationFilterChips(cs),
                  const SizedBox(height: 12),
                  Text(
                    'Priority',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildUrgencyFilterChips(cs),
                  const SizedBox(height: 12),
                  Text(
                    'Treatment Type',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildTreatmentTypeFilterChips(cs),
                ],
              ),
            ),
            crossFadeState: _isFilterExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),

          if (_isCalendarView)
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: VisualCalendarWidget(
                  appointments: appointments,
                  onAppointmentTap: (apt) {
                    context.push('/appointment/${apt.id}', extra: apt);
                  },
                  onEmptySlotTap: (slotTime) {
                    context.push('/booking');
                  },
                ),
              ),
            )
          else ...[
            // Tab bar selection
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
              ),
              child: TabBar(
                controller: _tabController,
                labelStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
                unselectedLabelStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  fontSize: 11.5,
                ),
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
                indicator: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                tabs: [
                  Tab(text: 'Upcoming (${upcoming.length})'),
                  Tab(text: 'Past (${past.length})'),
                  Tab(text: 'Cancelled (${cancelled.length})'),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _AppointmentListView(
                          appointments: upcoming,
                          onRefresh: () =>
                              ref.read(appointmentsProvider.notifier).load(),
                          emptyMessage: 'No upcoming appointments',
                          onRetryPayment: _retryPayment,
                          onDelete: _deleteAppointment,
                        ),
                        _AppointmentListView(
                          appointments: past,
                          onRefresh: () =>
                              ref.read(appointmentsProvider.notifier).load(),
                          emptyMessage: 'No past appointments',
                          onRetryPayment: _retryPayment,
                          onDelete: _deleteAppointment,
                        ),
                        _AppointmentListView(
                          appointments: cancelled,
                          onRefresh: () =>
                              ref.read(appointmentsProvider.notifier).load(),
                          emptyMessage: 'No cancelled appointments',
                          onRetryPayment: _retryPayment,
                          onDelete: _deleteAppointment,
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppointmentListView extends StatelessWidget {
  const _AppointmentListView({
    required this.appointments,
    required this.onRefresh,
    required this.emptyMessage,
    this.onRetryPayment,
    this.onDelete,
  });
  final List<Appointment> appointments;
  final Future<void> Function() onRefresh;
  final String emptyMessage;
  final Function(Appointment)? onRetryPayment;
  final Function(String)? onDelete;

  Future<void> _launchWhatsApp(
    BuildContext context,
    String phone,
    String patientName,
    String timeStr,
  ) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+|-|\(|\)'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No phone number available for WhatsApp.'),
        ),
      );
      return;
    }
    final message = Uri.encodeComponent(
      "Hello $patientName, this is a reminder for your appointment scheduled ($timeStr) at Gonstead Chiropractic Treatment. Thank you!",
    );
    String rawDigits = cleanPhone.replaceAll('+', '');
    if (rawDigits.startsWith('0')) {
      rawDigits = '92${rawDigits.substring(1)}';
    }
    final nativeUrl = "whatsapp://send?phone=$rawDigits&text=$message";
    final webUrl =
        "https://api.whatsapp.com/send?phone=$rawDigits&text=$message";
    final shortUrl = "https://wa.me/$rawDigits?text=$message";

    try {
      if (await canLaunchUrlString(nativeUrl)) {
        await launchUrlString(nativeUrl);
        return;
      }
      if (await canLaunchUrlString(webUrl)) {
        await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrlString(shortUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not launch WhatsApp. Please check if it is installed.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _makeCall(BuildContext context, String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+|-|\(|\)'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
      );
      return;
    }
    final url = 'tel:$cleanPhone';
    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        await launchUrlString(url);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 54,
              color: cs.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: GoogleFonts.poppins(
                color: cs.onSurface.withValues(alpha: 0.45),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        itemCount: appointments.length,
        itemBuilder: (_, i) {
          final apt = appointments[i];
          final sColor = statusColor(apt.status);
          final sBg = statusBgColor(apt.status);

          String dayStr = '?';
          String monthStr = '---';
          String timeStr = apt.time;

          if (apt.scheduledAt != null) {
            dayStr = DateFormat('d').format(apt.scheduledAt!);
            monthStr = DateFormat('MMM').format(apt.scheduledAt!).toUpperCase();
            timeStr = DateFormat('h:mm a').format(apt.scheduledAt!);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Dismissible(
              key: Key(apt.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
              ),
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      'Delete appointment',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
                    content: Text(
                      'Remove ${apt.patientName}\'s appointment?',
                      style: GoogleFonts.poppins(),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          'Delete',
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) => onDelete?.call(apt.id),
              child: PremiumCard(
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => context
                      .push('/appointment/${apt.id}')
                      .then((_) => onRefresh()),
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        // Elegant calendar-block indicator on the left
                        Container(
                          width: 58,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                dayStr,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                monthStr,
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  timeStr,
                                  style: GoogleFonts.poppins(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Center content
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
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (apt.isEmergency) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'EMG',
                                        style: GoogleFonts.poppins(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFFEF4444),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                apt.treatmentType,
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              // Payment Status Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: apt.paymentStatus == 'paid'
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: apt.paymentStatus == 'paid'
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : Colors.orange.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  apt.paymentStatus == 'paid'
                                      ? 'PAID'
                                      : 'UNPAID',
                                  style: GoogleFonts.poppins(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: apt.paymentStatus == 'paid'
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_rounded,
                                    size: 12,
                                    color: cs.onSurface.withValues(alpha: 0.4),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    apt.phoneNumber.isNotEmpty
                                        ? apt.phoneNumber
                                        : 'No phone number',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                              if (apt.paymentMethod == 'online' &&
                                  apt.paymentStatus == 'pending') ...[
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 26,
                                  child: TextButton.icon(
                                    onPressed: () => onRetryPayment?.call(apt),
                                    icon: const Icon(
                                      Icons.payment_rounded,
                                      size: 12,
                                    ),
                                    label: const Text('Pay Now'),
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.blueAccent
                                          .withValues(alpha: 0.1),
                                      foregroundColor: Colors.blueAccent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      textStyle: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status & Quick Navigation Actions on the right
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: sBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                apt.status,
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: sColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.call_rounded,
                                    size: 17,
                                    color: Color(0xFF10B981),
                                  ),
                                  onPressed: () =>
                                      _makeCall(context, apt.phoneNumber),
                                  tooltip: 'Call Patient',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 17,
                                    color: Color(0xFF25D366),
                                  ),
                                  onPressed: () => _launchWhatsApp(
                                    context,
                                    apt.phoneNumber,
                                    apt.patientName,
                                    timeStr,
                                  ),
                                  tooltip: 'WhatsApp',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.history_rounded,
                                    size: 17,
                                    color: cs.primary.withValues(alpha: 0.7),
                                  ),
                                  onPressed: () {
                                    context.push(
                                      '/patient-history?name=${Uri.encodeComponent(apt.patientName)}&phone=${Uri.encodeComponent(apt.phoneNumber)}',
                                    );
                                  },
                                  tooltip: 'Patient History',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
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
            ),
          );
        },
      ),
    );
  }
}
