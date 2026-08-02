import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/import_export_service.dart';
import '../../services/app_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../features/auth/auth_providers.dart';
import '../../models/app_user.dart';
import '../../models/appointment.dart';
import '../appointments/appointment_repository.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_repository.dart';
import '../../models/payment.dart';
import '../notes/clinical_notes_repository.dart';
import '../../services/repository_providers.dart';
import '../../services/notification_service.dart';
import '../../services/payment_gateway_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  AppointmentRepository get _repository =>
      ref.read(appointmentRepositoryProvider);
  PaymentRepository get _paymentRepository =>
      ref.read(paymentRepositoryProvider);
  List<Payment> _payments = [];
  bool _isLoading = false;

  Future<void> _exportMasterBackup() async {
    try {
      final prefs = await AppPreferences.instance.prefs;
      if (!mounted) return;

      // Parse Appointments
      final appointmentsRaw =
          prefs.getString('clinic_booked_appointments') ?? '[]';
      final List<dynamic> aptJson = jsonDecode(appointmentsRaw);
      final aptHeader = [
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
      final aptRows = <List<dynamic>>[aptHeader];
      for (final item in aptJson) {
        final map = Map<String, dynamic>.from(item as Map);
        aptRows.add([
          map['id'] ?? '',
          map['patientName'] ?? '',
          map['patientProfession'] ?? '',
          map['scheduledAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(DateTime.parse(map['scheduledAt']))
              : (map['time'] ?? ''),
          map['treatmentType'] ?? '',
          map['phoneNumber'] ?? '',
          map['email'] ?? '',
          map['status'] ?? '',
          (map['isEmergency'] == true) ? 'EMERGENCY' : 'Standard',
          map['visitReason'] ?? '',
          map['patientNote'] ?? '',
          map['cancellationReason'] ?? '',
          map['updatedAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(DateTime.parse(map['updatedAt']))
              : '',
        ]);
      }

      // Parse Payments
      final paymentsRaw = prefs.getString('clinic_patient_payments') ?? '[]';
      final List<dynamic> payJson = jsonDecode(paymentsRaw);
      final payHeader = [
        'Payment ID',
        'Patient Name',
        'Amount (PKR)',
        'Payment Method',
        'Status',
        'Note/Details',
        'Payment Date',
      ];
      final payRows = <List<dynamic>>[payHeader];
      for (final item in payJson) {
        final map = Map<String, dynamic>.from(item as Map);
        payRows.add([
          map['id'] ?? '',
          map['patientName'] ?? '',
          map['amount'] ?? 0.0,
          map['method'] ?? '',
          map['status'] ?? '',
          map['note'] ?? '',
          map['paidAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(DateTime.parse(map['paidAt']))
              : '',
        ]);
      }

      // Parse Clinical Notes
      final notesRaw = prefs.getString('clinic_clinical_notes') ?? '[]';
      final List<dynamic> notesJson = jsonDecode(notesRaw);
      final notesHeader = [
        'Note ID',
        'Patient Name',
        'Clinical Note',
        'Category',
        'Created At',
      ];
      final notesRows = <List<dynamic>>[notesHeader];
      for (final item in notesJson) {
        final map = Map<String, dynamic>.from(item as Map);
        notesRows.add([
          map['id'] ?? '',
          map['patientName'] ?? '',
          map['note'] ?? '',
          map['category'] ?? '',
          map['createdAt'] != null
              ? DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(DateTime.parse(map['createdAt']))
              : '',
        ]);
      }

      final success = await ImportExportService.exportExcel(
        context: context,
        defaultFileName: 'gct_clinic_master_export.xlsx',
        sheets: {
          'Appointments': aptRows,
          'Payments': payRows,
          'Clinical Notes': notesRows,
        },
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Master Export to Excel successfully exported! 💾'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Master Export failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _importMasterBackup() async {
    try {
      final excel = await ImportExportService.importExcel(context: context);
      if (excel == null) return;

      final prefs = await AppPreferences.instance.prefs;

      // 1. Import Appointments
      final aptRows = ImportExportService.parseSheet(
        excel: excel,
        sheetName: 'Appointments',
      );
      if (aptRows.isNotEmpty) {
        final List<Appointment> importedApts = [];
        for (final row in aptRows) {
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
          final cancellationReason =
              row['Cancellation Reason']?.toString() ?? '';
          final updatedRaw = row['Last Updated']?.toString() ?? '';

          DateTime? scheduledAt = DateTime.tryParse(scheduledRaw);
          DateTime? updatedAt = DateTime.tryParse(updatedRaw);

          if (patientName.isNotEmpty) {
            importedApts.add(
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
        await prefs.setString(
          'clinic_booked_appointments',
          jsonEncode(importedApts.map((a) => a.toJson()).toList()),
        );
      }

      // 2. Import Payments
      final payRows = ImportExportService.parseSheet(
        excel: excel,
        sheetName: 'Payments',
      );
      if (payRows.isNotEmpty) {
        final List<Payment> importedPays = [];
        for (final row in payRows) {
          final id = row['Payment ID']?.toString() ?? '';
          final patientName = row['Patient Name']?.toString() ?? '';
          final amount =
              double.tryParse(row['Amount (PKR)']?.toString() ?? '0') ?? 0.0;
          final method = row['Payment Method']?.toString() ?? 'Cash';
          final status = row['Status']?.toString() ?? 'Paid';
          final note = row['Note/Details']?.toString() ?? '';
          final paidRaw = row['Payment Date']?.toString() ?? '';

          DateTime paidAt = DateTime.tryParse(paidRaw) ?? DateTime.now();

          if (patientName.isNotEmpty) {
            final double pAmt = status.toLowerCase() == 'paid' ? amount : 0.0;
            importedPays.add(
              Payment(
                id: id.isNotEmpty ? id : Uuid().v4(),
                patientName: patientName,
                amount: amount,
                paidAmount: pAmt,
                paidAt: paidAt,
                method: method,
                status: status,
                note: note,
              ),
            );
          }
        }
        await prefs.setString(
          'clinic_patient_payments',
          jsonEncode(importedPays.map((p) => p.toJson()).toList()),
        );
      }

      // 3. Import Clinical Notes
      final noteRows = ImportExportService.parseSheet(
        excel: excel,
        sheetName: 'Clinical Notes',
      );
      if (noteRows.isNotEmpty) {
        final List<ClinicalNote> importedNotes = [];
        for (final row in noteRows) {
          final id = row['Note ID']?.toString() ?? '';
          final patientName = row['Patient Name']?.toString() ?? '';
          final note = row['Clinical Note']?.toString() ?? '';
          final category = row['Category']?.toString() ?? 'General';
          final createdRaw = row['Created At']?.toString() ?? '';

          DateTime createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();

          if (patientName.isNotEmpty) {
            importedNotes.add(
              ClinicalNote(
                id: id.isNotEmpty ? id : Uuid().v4(),
                patientName: patientName,
                note: note,
                category: category,
                createdAt: createdAt,
              ),
            );
          }
        }
        await prefs.setString(
          'clinic_clinical_notes',
          jsonEncode(importedNotes.map((n) => n.toJson()).toList()),
        );
      }

      await _loadAppointments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Master Backup restored successfully! 🔄'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Master Restore failed: ${e.toString()}')),
        );
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
        if (await canLaunchUrlString(url.toString())) {
          await launchUrlString(
            url.toString(),
            mode: LaunchMode.externalApplication,
          );
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

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    final appointments = await _repository.loadAppointments();
    final payments = await _paymentRepository.loadPayments();

    // Sync scheduled notifications in background on dashboard load
    unawaited(NotificationService().syncScheduledNotifications(appointments));
    unawaited(NotificationService().syncPaymentReminders(payments));

    // Save doctor's email to settings/clinic_config for staff group chat lookup
    if (!mounted) return;
    final user = ref.read(authStateProvider).asData?.value;
    if (user != null && user.email.isNotEmpty) {
      unawaited(
        FirebaseFirestore.instance
            .collection('settings')
            .doc('clinic_config')
            .set({
              'doctorEmail': user.email.trim().toLowerCase(),
            }, SetOptions(merge: true)),
      );
    }

    if (!mounted) return;
    setState(() {
      _payments = payments;
      _isLoading = false;
    });
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunchUrlString(url)) await launchUrlString(url);
  }

  Widget _buildPaymentRemindersBanner(ColorScheme cs) {
    final outstanding =
        _payments
            .where((p) => p.status != 'Paid' && p.reminderDate != null)
            .toList()
          ..sort((a, b) => a.reminderDate!.compareTo(b.reminderDate!));
    if (outstanding.isEmpty) return const SizedBox.shrink();

    final fmt = NumberFormat.currency(symbol: 'PKR ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm_on_rounded, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Payment Reminders',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.red.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...outstanding.take(2).map((p) {
              final isOverdue = p.reminderDate!.isBefore(DateTime.now());
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  '• ${p.patientName} owes PKR ${fmt.format(p.amount - p.paidAmount)} (Due: ${DateFormat('d MMM, h:mm a').format(p.reminderDate!)})',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.red.shade900,
                    fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final appointments = ref.watch(appointmentsProvider);
    final user =
        authState.asData?.value ??
        AppUser(
          uid: 'guest',
          email: 'guest@gonstead.com',
          displayName: 'Guest',
          phoneNumber: '',
        );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width > 720;

    // Reactive calculations
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final totalApts = appointments.length;
    final confirmedApts = appointments
        .where((a) => a.status.toLowerCase() == 'confirmed')
        .length;
    final pendingApts = appointments
        .where((a) => a.status.toLowerCase() == 'pending')
        .length;

    final totalPaid = appointments
        .where((a) => a.paymentStatus.toLowerCase() == 'paid')
        .fold<double>(0, (runningTotal, appointment) => runningTotal + appointment.amount);
    final totalPending = appointments
        .where((a) => a.paymentStatus.toLowerCase() == 'pending')
        .fold<double>(0, (runningTotal, appointment) => runningTotal + appointment.amount);
    final totalAll = appointments.fold<double>(0, (runningTotal, appointment) => runningTotal + appointment.amount);

    final todayAppointments = appointments.where((a) {
      if (a.scheduledAt == null) return false;
      return DateFormat('yyyy-MM-dd').format(a.scheduledAt!.toLocal()) ==
          todayStr;
    }).toList()..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));

    final now = DateTime.now();
    final upcomingList = appointments.where((a) {
      final d = a.scheduledAt;
      return d != null &&
          d.isAfter(now) &&
          a.status.toLowerCase() != 'cancelled' &&
          a.status.toLowerCase() != 'completed';
    }).toList()..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    final next = upcomingList.isNotEmpty ? upcomingList.first : null;

    return AppShellScaffold(
      title: 'Dashboard',
      currentRoute: '/dashboard',
      actions: [
        IconButton(
          icon: const Icon(Icons.forum_rounded),
          onPressed: () => context.push('/chat'),
          tooltip: 'Clinic Chat',
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded),
          onPressed: _exportMasterBackup,
          tooltip: 'Export Master Backup',
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_rounded),
          onPressed: _importMasterBackup,
          tooltip: 'Restore Master Backup',
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/booking'),
        label: Text(
          'Book Visit',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        icon: const Icon(Icons.add_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAppointments,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column (flex: 3)
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GreetingRow(
                            displayName: user.displayName.split(' ').first,
                          ),
                          const SizedBox(height: 14),
                          _buildPaymentRemindersBanner(cs),
                          if (next != null &&
                              next.scheduledAt != null &&
                              next.scheduledAt!
                                      .difference(DateTime.now())
                                      .inHours <
                                  24 &&
                              !next.scheduledAt!
                                  .difference(DateTime.now())
                                  .isNegative) ...[
                            _UpcomingNotificationBanner(appointment: next),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            children: [
                              _MiniStatCard(
                                label: 'Total',
                                value: totalApts,
                                icon: Icons.event_note_rounded,
                                color: cs.primary,
                              ),
                              _MiniStatCard(
                                label: 'Confirmed',
                                value: confirmedApts,
                                icon: Icons.check_circle_outline_rounded,
                                color: AppColors.statusConfirmed,
                              ),
                              _MiniStatCard(
                                label: 'Pending',
                                value: pendingApts,
                                icon: Icons.hourglass_top_rounded,
                                color: AppColors.statusPending,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _PaymentsQuickViewCard(
                            total: totalAll,
                            collected: totalPaid,
                            pending: totalPending,
                          ),
                          const SizedBox(height: 18),
                          _TodayScheduleTimeline(
                            appointments: todayAppointments,
                            onRefresh: _loadAppointments,
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(label: 'Next Appointment'),
                          const SizedBox(height: 10),
                          if (_isLoading)
                            const _SkeletonCard()
                          else if (next == null)
                            _EmptyNextCard(
                              onBook: () => context.push('/booking'),
                            )
                          else
                            _NextAppointmentCard(
                              appointment: next,
                              onTap: () =>
                                  context.push('/appointment/${next.id}'),
                              onRetryPayment: () => _retryPayment(next),
                            ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _SectionLabel(label: 'Upcoming Visits'),
                              TextButton(
                                onPressed: () => context.push('/appointments'),
                                child: const Text('See all'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_isLoading)
                            ...[1, 2].map(
                              (_) => const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: _SkeletonCard(),
                              ),
                            )
                          else if (appointments.isEmpty)
                            PremiumCard(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.event_busy_rounded,
                                    color: cs.onSurface.withValues(alpha: 0.3),
                                    size: 32,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'No visits booked yet',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Book your first appointment above',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.55,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...appointments
                                .take(5)
                                .map(
                                  (apt) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _AppointmentTile(
                                      appointment: apt,
                                      onDeleted: _loadAppointments,
                                      onRetryPayment: () => _retryPayment(apt),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right Column (flex: 2)
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(label: 'Quick Actions'),
                          const SizedBox(height: 10),
                          _QuickActionsGrid(onLaunchUrl: _launchUrl),
                          const SizedBox(height: 20),
                          _SectionLabel(label: 'Clinic Information'),
                          const SizedBox(height: 10),
                          _ClinicInfoCard(onLaunchUrl: _launchUrl),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GreetingRow(
                      displayName: user.displayName.split(' ').first,
                    ),
                    const SizedBox(height: 14),
                    _buildPaymentRemindersBanner(cs),
                    if (next != null &&
                        next.scheduledAt != null &&
                        next.scheduledAt!.difference(DateTime.now()).inHours <
                            24 &&
                        !next.scheduledAt!
                            .difference(DateTime.now())
                            .isNegative) ...[
                      _UpcomingNotificationBanner(appointment: next),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        _MiniStatCard(
                          label: 'Total',
                          value: totalApts,
                          icon: Icons.event_note_rounded,
                          color: cs.primary,
                        ),
                        _MiniStatCard(
                          label: 'Confirmed',
                          value: confirmedApts,
                          icon: Icons.check_circle_outline_rounded,
                          color: AppColors.statusConfirmed,
                        ),
                        _MiniStatCard(
                          label: 'Pending',
                          value: pendingApts,
                          icon: Icons.hourglass_top_rounded,
                          color: AppColors.statusPending,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PaymentsQuickViewCard(
                      total: totalAll,
                      collected: totalPaid,
                      pending: totalPending,
                    ),
                    const SizedBox(height: 18),
                    _TodayScheduleTimeline(
                      appointments: todayAppointments,
                      onRefresh: _loadAppointments,
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(label: 'Next Appointment'),
                    const SizedBox(height: 10),
                    if (_isLoading)
                      const _SkeletonCard()
                    else if (next == null)
                      _EmptyNextCard(onBook: () => context.push('/booking'))
                    else
                      _NextAppointmentCard(
                        appointment: next,
                        onTap: () => context.push('/appointment/${next.id}'),
                      ),
                    const SizedBox(height: 20),
                    _SectionLabel(label: 'Quick Actions'),
                    const SizedBox(height: 10),
                    _QuickActionsGrid(onLaunchUrl: _launchUrl),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SectionLabel(label: 'Upcoming Visits'),
                        TextButton(
                          onPressed: () => context.push('/appointments'),
                          child: const Text('See all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      ...[1, 2].map(
                        (_) => const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: _SkeletonCard(),
                        ),
                      )
                    else if (appointments.isEmpty)
                      PremiumCard(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              color: cs.onSurface.withValues(alpha: 0.3),
                              size: 32,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No visits booked yet',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Book your first appointment above',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...appointments
                          .take(5)
                          .map(
                            (apt) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _AppointmentTile(
                                appointment: apt,
                                onDeleted: _loadAppointments,
                                onRetryPayment: () => _retryPayment(apt),
                              ),
                            ),
                          ),
                    const SizedBox(height: 20),
                    _SectionLabel(label: 'Clinic Information'),
                    const SizedBox(height: 10),
                    _ClinicInfoCard(onLaunchUrl: _launchUrl),
                  ],
                ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2A40) : const Color(0xFFE8EFF8),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({required this.displayName});
  final String displayName;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          displayName,
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
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PremiumCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value.toString(),
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNextCard extends StatelessWidget {
  const _EmptyNextCard({required this.onBook});
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.event_available_rounded,
              color: cs.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No upcoming visits',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Schedule your next visit now',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onBook, child: const Text('Book')),
        ],
      ),
    );
  }
}

class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard({
    required this.appointment,
    required this.onTap,
    this.onRetryPayment,
  });
  final Appointment appointment;
  final VoidCallback onTap;
  final VoidCallback? onRetryPayment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final date = appointment.scheduledAt != null
        ? DateFormat('EEE, d MMM • hh:mm a').format(appointment.scheduledAt!)
        : appointment.time;
    final sColor = statusColor(appointment.status);
    final sBg = statusBgColor(appointment.status);

    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
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
                    appointment.patientName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    date,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    appointment.treatmentType,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: sBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    appointment.status,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: sColor,
                    ),
                  ),
                ),
                if (appointment.paymentMethod == 'online' &&
                    appointment.paymentStatus == 'pending') ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onRetryPayment,
                    icon: const Icon(Icons.payment_rounded, size: 14),
                    label: const Text('Pay Now'),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                      foregroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (appointment.isEmergency) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'EMG',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.onLaunchUrl});
  final Future<void> Function(String) onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width > 1000 ? 4 : (width > 720 ? 3 : 4);

    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.0,
      children: [
        _QuickAction(
          icon: Icons.calendar_month_rounded,
          label: 'Book',
          color: const Color(0xFF0A6BE8),
          onTap: () => context.push('/booking'),
        ),
        _QuickAction(
          icon: Icons.list_alt_rounded,
          label: 'Visits',
          color: const Color(0xFF6366F1),
          onTap: () => context.push('/appointments'),
        ),
        _QuickAction(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Pay',
          color: const Color(0xFF00A86B),
          onTap: () => context.push('/payments'),
        ),
        _QuickAction(
          icon: Icons.book_rounded,
          label: 'Notes',
          color: const Color(0xFFF59E0B),
          onTap: () => context.push('/notes'),
        ),
        _QuickAction(
          icon: Icons.calculate_rounded,
          label: 'Calc',
          color: const Color(0xFF8B5CF6),
          onTap: () => context.push('/calculator'),
        ),
        _QuickAction(
          icon: Icons.history_rounded,
          label: 'History',
          color: const Color(0xFF10B981),
          onTap: () => context.push('/patient-history'),
        ),
        _QuickAction(
          icon: Icons.forum_rounded,
          label: 'Chat',
          color: const Color(0xFF0E7490),
          onTap: () => context.push('/chat'),
        ),
        _QuickAction(
          icon: Icons.manage_accounts_rounded,
          label: 'Staff',
          color: const Color(0xFF0F7490),
          onTap: () => context.push('/staff-management'),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClinicInfoCard extends StatelessWidget {
  const _ClinicInfoCard({required this.onLaunchUrl});
  final Future<void> Function(String) onLaunchUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gonstead Chiropractic Treatment',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(
            icon: Icons.access_time_rounded,
            text: 'Mon – Sat  •  09:00 AM – 07:00 PM',
          ),
          const SizedBox(height: 6),
          _InfoLine(
            icon: Icons.location_on_rounded,
            text:
                'Tehsil Road, Near Peshawar Model School, Nowshera City, KPK.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onLaunchUrl('tel:+923046996267'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_rounded, size: 18),
                        const SizedBox(width: 6),
                        const Text('Call'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onLaunchUrl(
                    'https://maps.google.com/?q=Tehsil+Road+Nowshera',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.map_rounded, size: 18),
                        const SizedBox(width: 6),
                        const Text('Navigate'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: 0.45)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    this.onDeleted,
    this.onRetryPayment,
  });
  final Appointment appointment;
  final VoidCallback? onDeleted;
  final VoidCallback? onRetryPayment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sColor = statusColor(appointment.status);
    final sBg = statusBgColor(appointment.status);

    return Dismissible(
      key: Key(appointment.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.statusCancelled.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.statusCancelled,
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
              'Remove ${appointment.patientName}\'s appointment?',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: TextStyle(color: cs.error)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        await AppointmentRepository().deleteAppointment(appointment.id);
        onDeleted?.call();
      },
      child: PremiumCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: InkWell(
          onTap: () => context.push('/appointment/${appointment.id}'),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                child: Text(
                  appointment.patientName.isNotEmpty
                      ? appointment.patientName[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.poppins(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.patientName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${appointment.time}  •  ${appointment.treatmentType}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: cs.onSurface.withValues(alpha: 0.55),
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
                        color: appointment.paymentStatus == 'paid'
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: appointment.paymentStatus == 'paid'
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        appointment.paymentStatus == 'paid'
                            ? 'PAID (Online)'
                            : 'UNPAID (Cash)',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: appointment.paymentStatus == 'paid'
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ),
                    if (appointment.paymentMethod == 'online' &&
                        appointment.paymentStatus == 'pending') ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        child: ElevatedButton.icon(
                          onPressed: onRetryPayment,
                          icon: const Icon(Icons.payment_rounded, size: 12),
                          label: const Text('Pay Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (appointment.isEmergency) ...[
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
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  appointment.status,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: sColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingNotificationBanner extends StatelessWidget {
  const _UpcomingNotificationBanner({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final diff = appointment.scheduledAt!.difference(DateTime.now());
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final timeStr = hours > 0 ? '$hours hr $minutes min' : '$minutes min';

    return GestureDetector(
      onTap: () => context.push('/appointment/${appointment.id}'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFF97316).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFFEA580C),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'UPCOMING VISIT',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFEA580C),
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          timeStr,
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appointment.patientName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF431407),
                    ),
                  ),
                  Text(
                    '${appointment.treatmentType}  •  Today at ${appointment.time}',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: const Color(0xFF431407).withValues(alpha: 0.65),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentsQuickViewCard extends StatelessWidget {
  const _PaymentsQuickViewCard({
    required this.total,
    required this.collected,
    required this.pending,
  });
  final double total;
  final double collected;
  final double pending;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: cs.primary,
                size: 20,
              ),
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
              _buildStatItem('Total', total, cs.primary),
              _buildDivider(),
              _buildStatItem('Collected', collected, AppColors.statusConfirmed),
              _buildDivider(),
              _buildStatItem('Pending', pending, AppColors.statusPending),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 36,
      width: 1,
      color: Colors.grey.withValues(alpha: 0.2),
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  Widget _buildStatItem(String label, double amount, Color color) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'PKR ${fmt.format(amount)}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayScheduleTimeline extends StatelessWidget {
  const _TodayScheduleTimeline({
    required this.appointments,
    required this.onRefresh,
  });

  final List<Appointment> appointments;
  final VoidCallback onRefresh;

  Future<void> _launchWhatsApp(
    BuildContext context,
    String phone,
    String patientName,
    String dateStr,
  ) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+|-|\(|\)'), '');
    final message = Uri.encodeComponent(
      "Hello $patientName, this is a reminder for your chiropractic appointment scheduled on $dateStr at Gonstead Chiropractic Treatment. Please let us know if you need to reschedule. Thank you!",
    );
    String finalPhone = cleanPhone;
    if (!cleanPhone.startsWith('+') && !cleanPhone.startsWith('00')) {
      if (cleanPhone.startsWith('0')) {
        finalPhone = '+92${cleanPhone.substring(1)}';
      } else {
        finalPhone = '+92$cleanPhone';
      }
    }
    final url = "https://wa.me/${finalPhone.replaceAll('+', '')}?text=$message";
    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not launch WhatsApp. Please check if it is installed.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('WhatsApp launch failed: $e');
    }
  }

  Future<void> _makeCall(BuildContext context, String phone) async {
    final url = 'tel:$phone';
    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer.')),
        );
      }
    } catch (e) {
      debugPrint('Call launch failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (appointments.isEmpty) {
      return PremiumCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                color: cs.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "No appointments today",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    "Your schedule is free for the rest of today.",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                "Today's Schedule",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${appointments.length} Visits",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final apt = appointments[index];
              final timeStr = apt.scheduledAt != null
                  ? DateFormat('hh:mm a').format(apt.scheduledAt!.toLocal())
                  : apt.time;
              final isLast = index == appointments.length - 1;
              final sColor = statusColor(apt.status);

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Timeline line and bullet
                    Column(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sColor,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: sColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: cs.onSurface.withValues(alpha: 0.1),
                            ),
                          )
                        else
                          const SizedBox(height: 16),
                      ],
                    ),
                    const SizedBox(width: 14),
                    // Timeline content card
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: InkWell(
                          onTap: () => context
                              .push('/appointment/${apt.id}')
                              .then((_) => onRefresh()),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.05),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            timeStr,
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: cs.primary,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: sColor.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              apt.status,
                                              style: GoogleFonts.poppins(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: sColor,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: apt.paymentStatus == 'paid'
                                                  ? Colors.green.withValues(
                                                      alpha: 0.12,
                                                    )
                                                  : Colors.orange.withValues(
                                                      alpha: 0.12,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              apt.paymentStatus == 'paid'
                                                  ? 'PAID'
                                                  : 'UNPAID',
                                              style: GoogleFonts.poppins(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    apt.paymentStatus == 'paid'
                                                    ? Colors.green
                                                    : Colors.orange,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        apt.patientName,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        apt.treatmentType,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.55,
                                          ),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // Communication actions
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (apt.phoneNumber.isNotEmpty) ...[
                                      IconButton(
                                        icon: const Icon(
                                          Icons.phone_rounded,
                                          size: 16,
                                        ),
                                        color: cs.primary,
                                        onPressed: () =>
                                            _makeCall(context, apt.phoneNumber),
                                        style: IconButton.styleFrom(
                                          padding: const EdgeInsets.all(6),
                                          minimumSize: Size.zero,
                                          backgroundColor: cs.primary
                                              .withValues(alpha: 0.08),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.chat_bubble_rounded,
                                          size: 16,
                                        ),
                                        color: AppColors.statusConfirmed,
                                        onPressed: () => _launchWhatsApp(
                                          context,
                                          apt.phoneNumber,
                                          apt.patientName,
                                          apt.scheduledAt != null
                                              ? DateFormat(
                                                  'EEE d MMM hh:mm a',
                                                ).format(apt.scheduledAt!)
                                              : apt.time,
                                        ),
                                        style: IconButton.styleFrom(
                                          padding: const EdgeInsets.all(6),
                                          minimumSize: Size.zero,
                                          backgroundColor: AppColors
                                              .statusConfirmed
                                              .withValues(alpha: 0.08),
                                        ),
                                      ),
                                    ],
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
