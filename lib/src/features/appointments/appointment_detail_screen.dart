import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../models/appointment.dart';
import 'appointment_repository.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import 'pdf_generator.dart';
import '../../theme/app_theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repository_providers.dart';
import '../../services/notification_service.dart';

class AppointmentDetailScreen extends ConsumerStatefulWidget {
  const AppointmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends ConsumerState<AppointmentDetailScreen> {
  AppointmentRepository get _repo => ref.read(appointmentRepositoryProvider);
  final _noteController = TextEditingController();

  Future<void> _launchWhatsApp(String phone, String patientName, String dateStr) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+|-|\(|\)'), '');
    final message = Uri.encodeComponent(
        "Hello $patientName, this is a reminder for your chiropractic appointment scheduled on $dateStr at Gonstead Chiropractic Treatment. Please let us know if you need to reschedule. Thank you!");
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp. Please check if it is installed.')),
        );
      }
    } catch (e) {
      debugPrint('WhatsApp launch failed: $e');
    }
  }

  Future<void> _makeCall(String phone) async {
    final url = 'tel:$phone';
    try {
      if (await canLaunchUrlString(url)) {
        await launchUrlString(url);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer.')),
        );
      }
    } catch (e) {
      debugPrint('Call launch failed: $e');
    }
  }
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _treatmentController = TextEditingController();
  
  // Clinical report field controllers
  final _bpController = TextEditingController();
  final _pulseController = TextEditingController();
  final _segmentsController = TextEditingController();
  final _exercisesController = TextEditingController();
  final _followUpController = TextEditingController();
  final _professionController = TextEditingController();
  final _durationController = TextEditingController();
  double _painLevel = 0.0;

  final _formKey = GlobalKey<FormState>();

  Appointment? _appointment;
  bool _isEditing = false;
  bool _isLoading = true;
  String _statusValue = 'Pending';
  DateTime? _scheduledAt;

  // New state
  final _techniqueController = TextEditingController();
  final _improvementController = TextEditingController();
  String? _posturalPhotoPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _treatmentController.dispose();
    _bpController.dispose();
    _pulseController.dispose();
    _segmentsController.dispose();
    _exercisesController.dispose();
    _followUpController.dispose();
    _professionController.dispose();
    _durationController.dispose();
    _techniqueController.dispose();
    _improvementController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apt = await _repo.findById(widget.id);
    if (!mounted) return;
    setState(() {
      _appointment = apt;
      _noteController.text = apt?.patientNote ?? '';
      _nameController.text = apt?.patientName ?? '';
      _phoneController.text = apt?.phoneNumber ?? '';
      _emailController.text = apt?.email ?? '';
      _treatmentController.text = apt?.treatmentType ?? '';
      _statusValue = apt?.status ?? 'Pending';
      _scheduledAt = apt?.scheduledAt;
      
      // Initialize clinical assessment fields
      _painLevel = apt?.painLevel?.toDouble() ?? 0.0;
      _bpController.text = apt?.bloodPressure ?? '';
      _pulseController.text = apt?.pulseRate?.toString() ?? '';
      _segmentsController.text = apt?.adjustedSegments ?? '';
      _exercisesController.text = apt?.prescribedExercises ?? '';
      _followUpController.text = apt?.nextFollowUp ?? '';
      _professionController.text = apt?.patientProfession ?? '';
      _durationController.text = apt?.durationMinutes.toString() ?? '40';
      
      _isLoading = false;

      // Init new fields
      _techniqueController.text = apt?.adjustmentTechnique ?? '';
      _improvementController.text = apt?.patientImprovement ?? '';
      _posturalPhotoPath = apt?.posturalPhotoPath?.isNotEmpty == true ? apt!.posturalPhotoPath : null;
    });
  }

  Future<void> _checkCompletedAndPrompt(Appointment appointment) async {
    if (appointment.status.toLowerCase() == 'completed' &&
        appointment.treatmentPlanTotalSessions != null &&
        appointment.treatmentPlanTotalSessions! > 0) {
      final currentSession = appointment.sessionNumber ?? 1;
      final totalSessions = appointment.treatmentPlanTotalSessions!;
      if (currentSession < totalSessions) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.event_available_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Schedule Next Session', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18)),
                ),
              ],
            ),
            content: Text(
              'Session $currentSession of $totalSessions is completed!\n\n'
              'Would you like to schedule the next session (Session ${currentSession + 1} of $totalSessions) right now?',
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Maybe Later'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Schedule Now'),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          final extraData = {
            'patientName': appointment.patientName,
            'phoneNumber': appointment.phoneNumber,
            'email': appointment.email,
            'patientProfession': appointment.patientProfession,
            'treatmentType': appointment.treatmentType,
            'treatmentPlanTotalSessions': totalSessions,
            'sessionNumber': currentSession + 1,
            'durationMinutes': appointment.durationMinutes,
            'visitReason': 'Follow-up treatment session ${currentSession + 1} of $totalSessions.',
          };
          context.push('/booking', extra: extraData);
        }
      }
    }
  }

  Future<void> _saveEdits() async {
    if (_appointment == null) return;
    final updated = _appointment!.copyWith(
      patientName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      treatmentType: _treatmentController.text.trim(),
      status: _statusValue,
      scheduledAt: _scheduledAt ?? _appointment!.scheduledAt,
      painLevel: _painLevel.round(),
      bloodPressure: _bpController.text.trim(),
      pulseRate: int.tryParse(_pulseController.text.trim()),
      adjustedSegments: _segmentsController.text.trim(),
      prescribedExercises: _exercisesController.text.trim(),
      nextFollowUp: _followUpController.text.trim(),
      patientProfession: _professionController.text.trim(),
      durationMinutes: int.tryParse(_durationController.text.trim()) ?? _appointment!.durationMinutes,
      adjustmentTechnique: _techniqueController.text.trim(),
      patientImprovement: _improvementController.text.trim(),
      posturalPhotoPath: _posturalPhotoPath ?? '',
      updatedAt: DateTime.now(),
    );
    await _repo.updateAppointment(updated);

    // Manage scheduled reminder notifications
    try {
      // Cancel previous scheduled notifications if date/time changed or no longer active
      if (updated.scheduledAt != _appointment!.scheduledAt || updated.status.toLowerCase() != 'confirmed') {
        await NotificationService().cancelNotification(NotificationService.getReminderId(_appointment!.id));
        await NotificationService().cancelNotification(NotificationService.getStartId(_appointment!.id));
      }
      
      // Re-schedule reminder and appointment time notifications
      await NotificationService().scheduleAppointmentReminders(updated);

      // Show instant confirmation notification
      await NotificationService().showLocalNotification(
        'Appointment Updated ✏️',
        'Patient: ${updated.patientName} (${updated.status})',
        payload: '/appointment/${updated.id}',
      );
    } catch (e) {
      debugPrint('Notification setup failed: $e');
    }

    if (!mounted) return;
    setState(() { _appointment = updated; _isEditing = false; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment updated')));
    await _checkCompletedAndPrompt(updated);
  }

  Future<void> _saveNote() async {
    if (_appointment == null) return;
    final updated = _appointment!.copyWith(patientNote: _noteController.text.trim(), updatedAt: DateTime.now());
    await _repo.updateAppointment(updated);
    if (!mounted) return;
    setState(() => _appointment = updated);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved')));
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_appointment == null) return;
    final updated = _appointment!.copyWith(status: newStatus, updatedAt: DateTime.now());
    await _repo.updateAppointment(updated);

    try {
      // Cancel scheduled notifications if status is cancelled/completed/no show
      if (newStatus.toLowerCase() == 'cancelled' ||
          newStatus.toLowerCase() == 'completed' ||
          newStatus.toLowerCase() == 'no show') {
        await NotificationService().cancelNotification(NotificationService.getReminderId(updated.id));
        await NotificationService().cancelNotification(NotificationService.getStartId(updated.id));
      } else {
        // Reschedule notifications if changed back to Confirmed/Pending
        await NotificationService().scheduleAppointmentReminders(updated);
      }

      // Show instant notification
      await NotificationService().showLocalNotification(
        'Status Updated 🔄',
        '${updated.patientName}\'s appointment status changed to $newStatus.',
        payload: '/appointment/${updated.id}',
      );
    } catch (e) {
      debugPrint('Notification update failed: $e');
    }

    if (!mounted) return;
    setState(() => _appointment = updated);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status → $newStatus')));
    await _checkCompletedAndPrompt(updated);
  }

  Future<void> _deleteAppointment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Appointment', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('This will permanently delete this appointment.', style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (confirmed != true || _appointment == null) return;
    
    final oldAptId = _appointment!.id;
    await _repo.deleteAppointment(oldAptId);

    try {
      // Cancel scheduled reminder and start notifications
      await NotificationService().cancelNotification(NotificationService.getReminderId(oldAptId));
      await NotificationService().cancelNotification(NotificationService.getStartId(oldAptId));
      // Show instant notification
      await NotificationService().showLocalNotification(
        'Appointment Deleted 🗑️',
        'Appointment for ${_appointment!.patientName} has been deleted.',
        payload: '/dashboard',
      );
    } catch (e) {
      debugPrint('Notification delete failed: $e');
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? DateTime.now()));
    if (time == null) return;
    setState(() => _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _generatePdf() async {
    if (_appointment == null) return;
    try {
      final bytes = await generatePatientReportPdf(_appointment!);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: '${_appointment!.patientName}_REPORT',
      );
    } catch (e) {
      debugPrint('Error generating patient report PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e')),
        );
      }
    }
  }

  Future<void> _generateAllSessionsPdf() async {
    if (_appointment == null) return;
    try {
      final allApts = await _repo.loadAppointments();
      
      // Find all sessions for this patient
      final patientName = _appointment!.patientName.toLowerCase();
      final patientPhone = _appointment!.phoneNumber;
      final patientSessions = allApts.where((a) {
        final nameMatch = a.patientName.toLowerCase() == patientName;
        final phoneMatch = patientPhone.isNotEmpty && a.phoneNumber == patientPhone;
        return nameMatch || phoneMatch;
      }).toList();

      // Sort by scheduled date
      patientSessions.sort((a, b) {
        if (a.scheduledAt == null && b.scheduledAt == null) return 0;
        if (a.scheduledAt == null) return 1;
        if (b.scheduledAt == null) return -1;
        return a.scheduledAt!.compareTo(b.scheduledAt!);
      });

      if (patientSessions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No sessions found for this patient.')),
          );
        }
        return;
      }

      final bytes = await generateAllSessionsReportPdf(patientSessions);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: '${_appointment!.patientName}_ALL_SESSIONS_REPORT',
      );
    } catch (e) {
      debugPrint('Error generating all sessions PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate comprehensive report: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)));
    final apt = _appointment;
    if (apt == null) return AppShellScaffold(title: 'Appointment', currentRoute: '/dashboard', body: const Center(child: Text('Not found')));

    final cs = Theme.of(context).colorScheme;
    final dateText = apt.scheduledAt != null ? DateFormat('EEEE, d MMM y  •  hh:mm a').format(apt.scheduledAt!) : apt.time;
    final sColor = statusColor(apt.status);
    final sBg = statusBgColor(apt.status);

    return AppShellScaffold(
      title: 'Appointment Detail',
      currentRoute: '/dashboard',
      actions: [
        IconButton(icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _generatePdf, tooltip: 'PDF'),
        PopupMenuButton<String>(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) async {
            if (v == 'edit') setState(() => _isEditing = true);
            if (v == 'confirm') await _updateStatus('Confirmed');
            if (v == 'complete') await _updateStatus('Completed');
            if (v == 'cancel') await _updateStatus('Cancelled');
            if (v == 'no_show') await _updateStatus('No Show');
            if (v == 'delete') await _deleteAppointment();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'confirm', child: Text('Mark Confirmed')),
            const PopupMenuItem(value: 'complete', child: Text('Mark Completed')),
            const PopupMenuItem(value: 'cancel', child: Text('Cancel Appointment')),
            const PopupMenuItem(value: 'no_show', child: Text('Mark No Show')),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status timeline
          _StatusTimeline(status: apt.status),
          const SizedBox(height: 14),

          // Main card
          PremiumCard(
            padding: const EdgeInsets.all(20),
            child: _isEditing ? _buildEditForm() : _buildViewCard(apt, cs, dateText, sColor, sBg),
          ),
          const SizedBox(height: 14),

          // Treatment Plan Progress Card
          if (!_isEditing && apt.treatmentPlanTotalSessions != null && apt.treatmentPlanTotalSessions! > 0) ...[
            PremiumCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Care Plan: ${apt.treatmentPlanTotalSessions} Sessions',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Session Number: Session ${apt.sessionNumber ?? 1}',
                              style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface.withOpacity(0.55)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${apt.treatmentPlanTotalSessions! > 0 ? (((apt.sessionNumber ?? 1) / apt.treatmentPlanTotalSessions!) * 100).round() : 0}% Progress',
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: apt.treatmentPlanTotalSessions! > 0 ? (apt.sessionNumber ?? 1) / apt.treatmentPlanTotalSessions! : 0.0,
                      minHeight: 10,
                      backgroundColor: cs.primary.withOpacity(0.1),
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Completed: ${apt.sessionNumber ?? 1} sessions',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withOpacity(0.65)),
                      ),
                      Text(
                        'Remaining: ${(apt.treatmentPlanTotalSessions! - (apt.sessionNumber ?? 1)).clamp(0, apt.treatmentPlanTotalSessions!)} sessions',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withOpacity(0.65)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Quick action buttons
          if (!_isEditing) ...[
            Row(children: [
              _QuickBtn(icon: Icons.check_circle_outline_rounded, label: 'Confirm', color: AppColors.statusConfirmed, onTap: () => _updateStatus('Confirmed')),
              const SizedBox(width: 10),
              _QuickBtn(icon: Icons.task_alt_rounded, label: 'Complete', color: AppColors.statusCompleted, onTap: () => _updateStatus('Completed')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _QuickBtn(icon: Icons.person_off_rounded, label: 'No Show', color: const Color(0xFF8B5CF6), onTap: () => _updateStatus('No Show')),
              const SizedBox(width: 10),
              _QuickBtn(icon: Icons.picture_as_pdf_rounded, label: 'PDF Report', color: cs.primary, onTap: _generatePdf),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _QuickBtn(icon: Icons.summarize_rounded, label: 'All Sessions PDF', color: const Color(0xFFD97706), onTap: _generateAllSessionsPdf),
              const SizedBox(width: 10),
              _QuickBtn(
                icon: Icons.history_rounded,
                label: 'Patient History',
                color: cs.primary,
                onTap: () {
                  context.push('/patient-history?name=${Uri.encodeComponent(apt.patientName)}&phone=${Uri.encodeComponent(apt.phoneNumber)}').then((_) => _load());
                },
              ),
            ]),
            const SizedBox(height: 16),
            Text('Clinical Assessment & Treatment', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            PremiumCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vitals row
                  Row(
                    children: [
                      Expanded(
                        child: _buildClinicalIndicator(
                          icon: Icons.favorite_rounded,
                          label: 'Pulse Rate',
                          value: apt.pulseRate != null ? '${apt.pulseRate} bpm' : 'Not recorded',
                          color: Colors.redAccent,
                        ),
                      ),
                      Expanded(
                        child: _buildClinicalIndicator(
                          icon: Icons.speed_rounded,
                          label: 'Blood Pressure',
                          value: apt.bloodPressure.isNotEmpty ? apt.bloodPressure : 'Not recorded',
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Pain score visual indicator
                  Text('Pain Severity (VAS)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (apt.painLevel ?? 0) / 10,
                            minHeight: 8,
                            backgroundColor: cs.surfaceVariant,
                            color: _getPainColor(apt.painLevel ?? 0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${apt.painLevel ?? 0}/10',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: _getPainColor(apt.painLevel ?? 0)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  // Patient Improvement rating
                  if (apt.patientImprovement.isNotEmpty)
                    _DetailRow(
                      icon: Icons.trending_up_rounded,
                      label: 'Improvement',
                      value: apt.patientImprovement,
                    ),
                  // Adjustment Technique
                  if (apt.adjustmentTechnique.isNotEmpty)
                    _DetailRow(
                      icon: Icons.tune_rounded,
                      label: 'Technique',
                      value: apt.adjustmentTechnique,
                    ),
                  // Spinal Adjustments
                  _DetailRow(
                    icon: Icons.accessibility_new_rounded,
                    label: 'Adjustments',
                    value: apt.adjustedSegments.isNotEmpty ? apt.adjustedSegments : 'No segments recorded',
                  ),
                  // Prescribed Exercises
                  _DetailRow(
                    icon: Icons.directions_run_rounded,
                    label: 'Exercises',
                    value: apt.prescribedExercises.isNotEmpty ? apt.prescribedExercises : 'None prescribed',
                  ),
                  // Follow up
                  _DetailRow(
                    icon: Icons.next_plan_outlined,
                    label: 'Follow-up',
                    value: apt.nextFollowUp.isNotEmpty ? apt.nextFollowUp : 'As needed',
                  ),
                  // Posture Photo
                  if (apt.posturalPhotoPath.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Posture Photo', style: GoogleFonts.poppins(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(apt.posturalPhotoPath),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: cs.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(child: Text('Photo not available', style: GoogleFonts.poppins(fontSize: 12))),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          Text('Clinical Note', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _noteController,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Add clinical note…', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _saveNote, child: const Text('Save Note'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _generatePdf, child: const Text('Report'))),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildViewCard(Appointment apt, ColorScheme cs, String dateText, Color sColor, Color sBg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (apt.isEmergency) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Text(
                  'CRITICAL EMERGENCY APPOINTMENT',
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444), letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ],
        Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: cs.primary.withValues(alpha: 0.12),
            child: Text(apt.patientName.isNotEmpty ? apt.patientName[0].toUpperCase() : '?', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: cs.primary)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(apt.patientName, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: sBg, borderRadius: BorderRadius.circular(20)), child: Text(apt.status, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: sColor))),
          ])),
        ]),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        _DetailRow(icon: Icons.calendar_today_rounded, label: 'Date', value: dateText),
        _DetailRow(icon: Icons.timer_outlined, label: 'Duration', value: '${apt.durationMinutes} minutes'),
        _DetailRow(icon: Icons.medical_services_outlined, label: 'Treatment', value: apt.treatmentType),
        if (apt.dateOfBirth != null)
          _DetailRow(
            icon: Icons.cake_rounded,
            label: 'DOB / Age',
            value: '${DateFormat('d MMM y').format(apt.dateOfBirth!)}  •  ${DateTime.now().year - apt.dateOfBirth!.year} yrs',
          ),
        if (apt.phoneNumber.isNotEmpty)
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: apt.phoneNumber,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.phone_rounded, size: 15),
                  color: cs.primary,
                  onPressed: () => _makeCall(apt.phoneNumber),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    backgroundColor: cs.primary.withOpacity(0.08),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                  color: AppColors.statusConfirmed,
                  onPressed: () => _launchWhatsApp(
                    apt.phoneNumber,
                    apt.patientName,
                    apt.scheduledAt != null
                        ? DateFormat('EEEE, d MMM y • hh:mm a').format(apt.scheduledAt!)
                        : apt.time,
                  ),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    backgroundColor: AppColors.statusConfirmed.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),
        if (apt.email.isNotEmpty) _DetailRow(icon: Icons.mail_outline_rounded, label: 'Email', value: apt.email),
        if (apt.visitReason.isNotEmpty) _DetailRow(icon: Icons.edit_note_rounded, label: 'Reason', value: apt.visitReason),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () => setState(() => _isEditing = true), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Edit Appointment')),
      ],
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit Appointment', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Patient name', prefixIcon: Icon(Icons.person_outline_rounded))),
          const SizedBox(height: 10),
          TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined))),
          const SizedBox(height: 10),
          TextFormField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded))),
          const SizedBox(height: 10),
          _buildDropdownTextField(
            controller: _professionController,
            labelText: 'Profession',
            prefixIcon: Icons.work_outline_rounded,
            options: [
              'Engineer', 'Doctor', 'Teacher', 'Student', 'Office Worker', 'Driver', 'Laborer', 'Retired', 'Housewife',
              'Businessman', 'Nurse', 'Salesperson', 'Accountant', 'Builder/Mason', 'Farmer', 'Unemployed', 'Self-employed',
              'Artist', 'Software Developer', 'Security Guard', 'Police Officer', 'Soldier', 'Tailor', 'Shopkeeper', 'Chef', 'Other'
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(controller: _treatmentController, decoration: const InputDecoration(labelText: 'Treatment', prefixIcon: Icon(Icons.medical_services_outlined))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickDateTime,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(_scheduledAt != null ? DateFormat('d MMM y • hh:mm a').format(_scheduledAt!) : 'Change date & time'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _statusValue,
            decoration: const InputDecoration(labelText: 'Status'),
            items: ['Pending', 'Confirmed', 'Completed', 'Cancelled', 'No Show'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins()))).toList(),
            onChanged: (v) => setState(() => _statusValue = v ?? _statusValue),
          ),
          const SizedBox(height: 10),
          // Duration editor
          TextFormField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Duration (minutes)',
              prefixIcon: const Icon(Icons.timer_outlined),
              suffixIcon: PopupMenuButton<int>(
                icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                onSelected: (val) {
                  _durationController.text = val.toString();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 20, child: Text('20 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                  PopupMenuItem(value: 40, child: Text('40 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                  PopupMenuItem(value: 60, child: Text('60 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                  PopupMenuItem(value: 80, child: Text('80 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          Text('Clinical Assessment & Treatment', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          
          // Pain level slider
          Row(
            children: [
              Text('Pain Level: ', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${_painLevel.round()}/10', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: _getPainColor(_painLevel.round()))),
            ],
          ),
          Slider(
            value: _painLevel,
            min: 0,
            max: 10,
            divisions: 10,
            activeColor: _getPainColor(_painLevel.round()),
            onChanged: (v) => setState(() => _painLevel = v),
          ),
          const SizedBox(height: 10),

          // Adjustment Technique dropdown
          _buildDropdownTextField(
            controller: _techniqueController,
            labelText: 'Adjustment Technique',
            prefixIcon: Icons.tune_rounded,
            hintText: 'e.g. Gonstead, Diversified',
            options: [
              'Gonstead Technique',
              'Diversified Technique',
              'Drop Table (Thompson)',
              'Activator Method',
              'SOT (Sacro-Occipital Technique)',
              'Flexion-Distraction (Cox)',
              'Upper Cervical (NUCCA)',
              'Toggle Recoil',
              'Logan Basic',
              'Applied Kinesiology',
              'Webster Technique',
              'Myofascial Release',
              'Soft Tissue Mobilisation',
              'PIR (Post-Isometric Relaxation)',
              'Full Spine Adjustment',
            ],
          ),
          const SizedBox(height: 10),

          // Patient Improvement
          _buildDropdownTextField(
            controller: _improvementController,
            labelText: 'Patient Improvement vs Last Visit',
            prefixIcon: Icons.trending_up_rounded,
            hintText: 'How does patient feel?',
            options: [
              'Much Better — Significant improvement',
              'Better — Noticeable improvement',
              'Slightly Better — Minor improvement',
              'Same — No change',
              'Slightly Worse — Minor regression',
              'Worse — Noticeable regression',
              'First Visit — No comparison',
            ],
          ),
          const SizedBox(height: 10),

          // Posture Photo in edit mode
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_camera_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Posture Photo', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_posturalPhotoPath != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => setState(() => _posturalPhotoPath = null),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_posturalPhotoPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_posturalPhotoPath!),
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: const Text('Camera'),
                        onPressed: () async {
                          final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
                          if (img != null) setState(() => _posturalPhotoPath = img.path);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text('Gallery'),
                        onPressed: () async {
                          final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
                          if (img != null) setState(() => _posturalPhotoPath = img.path);
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Vitals (BP & Pulse)
          Row(
            children: [
              Expanded(
                child: _buildDropdownTextField(
                  controller: _bpController,
                  labelText: 'Blood Pressure',
                  prefixIcon: Icons.speed_rounded,
                  hintText: 'e.g. 120/80',
                  options: [
                    '120/80 (Normal)', '110/70 (Optimal)', '115/75 (Healthy)', '100/60 (Hypotension)',
                    '130/85 (Prehypertension)', '135/85 (Prehypertension)', '140/90 (Stage 1)',
                    '145/90 (Stage 1)', '150/95 (Stage 2)', '160/100 (Stage 2)', '180/120 (Hypertensive Crisis)'
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdownTextField(
                  controller: _pulseController,
                  labelText: 'Pulse (bpm)',
                  prefixIcon: Icons.favorite_rounded,
                  keyboardType: TextInputType.number,
                  hintText: 'e.g. 72',
                  options: [
                    '50 (Bradycardia/Athlete)', '55', '60 (Normal)', '65', '70', '72',
                    '75', '80', '85', '90', '95', '100 (Tachycardia)', '105', '110'
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Spinal segments adjusted
          _buildDropdownTextField(
            controller: _segmentsController,
            labelText: 'Adjusted Spinal Segments',
            prefixIcon: Icons.accessibility_new_rounded,
            hintText: 'e.g. C2, L5, Pelvis',
            options: [
              'C1 (Atlas)', 'C2 (Axis)', 'C3', 'C4', 'C5', 'C6', 'C7', 'T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8',
              'T9', 'T10', 'T11', 'T12', 'L1', 'L2', 'L3', 'L4', 'L5', 'Sacrum', 'Coccyx', 'Pelvis', 'Left Ilium', 'Right Ilium',
              'Occiput', 'Cervicothoracic Junction', 'Thoracolumbar Junction', 'Lumbosacral Junction', 'Sacroiliac (SI) Joint', 'Full Spine Adjustment'
            ],
          ),
          const SizedBox(height: 10),

          // Exercises
          _buildDropdownTextField(
            controller: _exercisesController,
            labelText: 'Prescribed Exercises / Care Tips',
            prefixIcon: Icons.directions_run_rounded,
            options: [
              'Neck Retractions / Chin Tucks (3x daily)',
              'Hamstring Stretch (2x daily)',
              'Cat-Cow Stretch (10 reps)',
              'Child\'s Pose (30 sec hold)',
              'Postural Correction Exercises',
              'Lumbar Extension Stretch (McKenzie)',
              'Pelvic Tilts (15 reps)',
              'Ice Pack on affected area (15 mins on/off)',
              'Heat Pack to relax muscles (20 mins)',
              'Ergonomic chair setup adjustment',
              'Avoid heavy lifting / bending forward',
              'Take active walking breaks every 45 mins',
              'Perform gentle neck rolls',
              'Core strengthening (Planks/Bird-dog)',
              'Scapular Squeezes (15 reps)',
              'Pectoralis Stretch in doorway',
              'Stay hydrated & sleep on back/side'
            ],
          ),
          const SizedBox(height: 10),

          // Follow-up
          _buildDropdownTextField(
            controller: _followUpController,
            labelText: 'Next Follow-up Plan',
            prefixIcon: Icons.next_plan_outlined,
            hintText: 'e.g. 1 week, as needed',
            options: [
              'Tomorrow', '2 days', '3 days', '5 days', '1 week', '10 days', '2 weeks',
              '3 weeks', '4 weeks', '6 weeks', '2 months', '3 months', 'Maintenance (Monthly)',
              'Wellness Checkup', 'As needed (PRN)', 'Discharged from care'
            ],
          ),
          const SizedBox(height: 18),
          
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _isEditing = false), child: const Text('Cancel'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: _saveEdits, child: const Text('Save'))),
          ]),
        ],
      ),
    );
  }

  Color _getPainColor(int score) {
    if (score <= 3) return Colors.green;
    if (score <= 6) return Colors.orange;
    return Colors.red;
  }

  Widget _buildClinicalIndicator({required IconData icon, required String label, required String value, required Color color}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.poppins(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
              Text(value, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    required List<String> options,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(prefixIcon),
        suffixIcon: PopupMenuButton<String>(
          icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
          onSelected: (val) {
            controller.text = val;
            onChanged?.call(val);
          },
          itemBuilder: (BuildContext context) {
            return options.map((String choice) {
              return PopupMenuItem<String>(
                value: choice,
                child: Text(choice, style: GoogleFonts.poppins(fontSize: 13)),
              );
            }).toList();
          },
        ),
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    const steps = ['Pending', 'Confirmed', 'Completed'];
    final cs = Theme.of(context).colorScheme;
    final currentIdx = steps.indexWhere((s) => s.toLowerCase() == status.toLowerCase());
    final isCancelled = status.toLowerCase() == 'cancelled';

    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isCancelled ? Icons.cancel_rounded : Icons.timeline_rounded, size: 18, color: isCancelled ? AppColors.statusCancelled : cs.primary),
          const SizedBox(width: 8),
          Text(isCancelled ? 'Appointment Cancelled' : 'Appointment Progress', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        if (!isCancelled) ...[
          const SizedBox(height: 14),
          Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              if (i.isOdd) {
                return Expanded(child: Container(height: 2, color: (i ~/ 2) < currentIdx ? AppColors.statusConfirmed : AppColors.grey200));
              }
              final idx = i ~/ 2;
              final done = idx <= currentIdx;
              final curr = idx == currentIdx;
              return Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: curr ? 30 : 24,
                  height: curr ? 30 : 24,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: done ? AppColors.statusConfirmed : AppColors.grey200, boxShadow: curr ? [BoxShadow(color: AppColors.statusConfirmed.withValues(alpha: 0.35), blurRadius: 8)] : []),
                  child: Center(child: Icon(Icons.check_rounded, size: 14, color: done ? Colors.white : AppColors.grey400)),
                ),
                const SizedBox(height: 4),
                Text(steps[idx], style: GoogleFonts.poppins(fontSize: 10, fontWeight: curr ? FontWeight.w600 : FontWeight.w400, color: done ? AppColors.statusConfirmed : AppColors.grey400)),
              ]);
            }),
          ),
        ],
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value, this.trailing});
  final IconData icon; final String label; final String value; final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(icon, size: 17, color: cs.onSurface.withValues(alpha: 0.45)),
        const SizedBox(width: 10),
        SizedBox(width: 68, child: Text(label, style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)))),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  const _QuickBtn({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon; final String label; final Color color; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.25))),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }
}
