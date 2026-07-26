import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../features/shared/widgets/app_shell_scaffold.dart';
import '../../features/shared/widgets/premium_card.dart';
import '../../models/appointment.dart';
import '../../utils/validators.dart';
import 'appointment_repository.dart';
import '../../theme/app_theme.dart';
import '../../services/repository_providers.dart';
import '../../services/notification_service.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, this.initialData});
  final Map<String, dynamic>? initialData;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _professionController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  final _sessionNumberController = TextEditingController(text: '1');
  final _totalSessionsController = TextEditingController();
  final _durationController = TextEditingController(text: '40');
  
  AppointmentRepository get _repository => ref.read(appointmentRepositoryProvider);

  int _step = 0; // 0=info, 1=schedule, 2=confirm
  String _service = 'Gonstead Adjustment';
  DateTime? _selectedDate;
  String? _selectedSlot;
  bool _isSubmitting = false;
  bool _isEmergency = false;

  int? _treatmentPlanTotalSessions;
  int? _sessionNumber;
  int _durationMinutes = 40;

  // New fields
  DateTime? _selectedDob;
  String? _posturalPhotoPath;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  // Time slots 9am–7pm every 30 min (customizable/overrideable on conflicts)
  static final List<String> _slots = [
    '09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM',
    '11:00 AM', '11:30 AM', '12:00 PM', '12:30 PM',
    '01:00 PM', '01:30 PM', '02:00 PM', '02:30 PM',
    '03:00 PM', '03:30 PM', '04:00 PM', '04:30 PM',
    '05:00 PM', '05:30 PM', '06:00 PM', '06:30 PM',
  ];

  static const List<String> _services = [
    'Gonstead Adjustment',
    'Spinal Screening',
    'Posture Assessment',
    'Full Consultation',
    'Follow-up Visit',
  ];

  static const List<Color> _serviceColors = [
    Color(0xFF0A6BE8), Color(0xFF6366F1), Color(0xFF00A86B),
    Color(0xFFF59E0B), Color(0xFF8B5CF6),
  ];

  static const List<IconData> _serviceIcons = [
    Icons.self_improvement_rounded,
    Icons.monitor_heart_rounded,
    Icons.accessibility_new_rounded,
    Icons.medical_information_rounded,
    Icons.replay_rounded,
  ];

  // Generate next 14 days
  List<DateTime> get _dateOptions {
    final now = DateTime.now();
    return List.generate(14, (i) => now.add(Duration(days: i + 1)));
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    if (widget.initialData != null) {
      _nameController.text = widget.initialData!['patientName']?.toString() ?? '';
      _phoneController.text = widget.initialData!['phoneNumber']?.toString() ?? '';
      _emailController.text = widget.initialData!['email']?.toString() ?? '';
      _professionController.text = widget.initialData!['patientProfession']?.toString() ?? '';
      _service = widget.initialData!['treatmentType']?.toString() ?? 'Gonstead Adjustment';
      _treatmentPlanTotalSessions = widget.initialData!['treatmentPlanTotalSessions'] as int?;
      if (_treatmentPlanTotalSessions != null) {
        _totalSessionsController.text = _treatmentPlanTotalSessions!.toString();
      }
      _sessionNumber = widget.initialData!['sessionNumber'] as int?;
      if (_sessionNumber != null) {
        _sessionNumberController.text = _sessionNumber!.toString();
      }
      _reasonController.text = widget.initialData!['visitReason']?.toString() ?? 'Next follow-up treatment session.';
      if (widget.initialData!['durationMinutes'] != null) {
        _durationMinutes = widget.initialData!['durationMinutes'] as int;
        _durationController.text = _durationMinutes.toString();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _professionController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    _sessionNumberController.dispose();
    _totalSessionsController.dispose();
    _durationController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _goStep(int step) {
    _animController.forward(from: 0);
    setState(() => _step = step);
  }

  bool _canGoToStep1() {
    if (!_formKey.currentState!.validate()) return false;
    return true;
  }

  Future<void> _submitBooking() async {
    if (_selectedDate == null || _selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date and time slot.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final slotParts = _selectedSlot!.split(' ');
      final timeParts = slotParts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      if (slotParts[1] == 'PM' && hour != 12) hour += 12;
      if (slotParts[1] == 'AM' && hour == 12) hour = 0;

      final scheduledDateTime = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
        hour, minute,
      );
      final formattedDate = DateFormat('EEE, d MMM').format(_selectedDate!);

      final appointments = await _repository.loadAppointments();

      // Check conflict: Active appointments that are NOT cancelled AND NOT rejected
      final activeAppointments = appointments.where((a) =>
          a.status.toLowerCase() != 'cancelled' &&
          a.status.toLowerCase() != 'rejected' &&
          a.scheduledAt != null).toList();

      Appointment? conflict;
      for (final appt in activeAppointments) {
        final diff = scheduledDateTime.difference(appt.scheduledAt!).inMinutes.abs();
        final requiredGap = _durationMinutes;
        if (diff < requiredGap) {
          conflict = appt;
          break;
        }
      }

      if (conflict != null) {
        // Suggest the next available slot
        DateTime nextAvailable = scheduledDateTime;
        bool hasConflict = true;
        while (hasConflict) {
          hasConflict = false;
          for (final appt in activeAppointments) {
            final diff = nextAvailable.difference(appt.scheduledAt!).inMinutes.abs();
            final requiredGap = _durationMinutes;
            if (diff < requiredGap) {
              nextAvailable = appt.scheduledAt!.add(Duration(minutes: requiredGap));
              hasConflict = true;
              break;
            }
          }
        }

        final suggestedDateText = DateFormat('EEEE, d MMMM y').format(nextAvailable);
        final suggestedTimeText = DateFormat('hh:mm a').format(nextAvailable);

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Booking Conflict', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18)),
                  ),
                ],
              ),
              content: Text(
                'This time slot conflicts with an existing appointment (enforcing $_durationMinutes-minute gap):\n\n'
                '• Patient: ${conflict!.patientName}\n'
                '• Booked Time: ${DateFormat('hh:mm a').format(conflict!.scheduledAt!)}\n\n'
                'The next available conflict-free slot is:\n'
                '• $suggestedDateText at $suggestedTimeText\n\n'
                'Would you like to book this suggested slot instead?',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedDate = nextAvailable;
                      _selectedSlot = suggestedTimeText;
                      _step = 2; // Jump to Review step
                    });
                  },
                  child: const Text('Use Suggested Slot'),
                ),
              ],
            ),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      int seq = appointments.length + 1;
      String formattedId = 'GCT-NSR-${seq.toString().padLeft(4, '0')}';
      while (appointments.any((a) => a.id == formattedId)) {
        seq++;
        formattedId = 'GCT-NSR-${seq.toString().padLeft(4, '0')}';
      }

      final newAppt = Appointment(
        id: formattedId,
        patientName: _nameController.text.trim(),
        time: '$formattedDate • $_selectedSlot',
        treatmentType: _service,
        status: 'Pending',
        scheduledAt: scheduledDateTime,
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        visitReason: _reasonController.text.trim(),
        patientNote: _notesController.text.trim(),
        updatedAt: DateTime.now(),
        isEmergency: _isEmergency,
        patientProfession: _professionController.text.trim(),
        treatmentPlanTotalSessions: _treatmentPlanTotalSessions,
        sessionNumber: _sessionNumber,
        durationMinutes: _durationMinutes,
        dateOfBirth: _selectedDob,
        posturalPhotoPath: _posturalPhotoPath ?? '',
      );

      await _repository.saveAppointment(newAppt);
 
      // Trigger instant booking notification
      try {
        await NotificationService().showLocalNotification(
          'Appointment Booked! 📅',
          'Patient: ${_nameController.text.trim()} • $_selectedSlot on $formattedDate',
          payload: '/appointment/$formattedId',
        );
 
        // Schedule dynamic alarm/notification reminders
        await NotificationService().scheduleAppointmentReminders(newAppt);
      } catch (e) {
        debugPrint('Failed to trigger local notifications: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment booked successfully! ✅')),
      );
      context.go('/dashboard');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: ${error.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      title: 'Book Appointment',
      currentRoute: '/booking',
      body: Column(
        children: [
          // Step indicator
          _StepIndicator(currentStep: _step),

          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: _step == 0
                      ? _buildStep0(cs)
                      : _step == 1
                          ? _buildStep1(cs)
                          : _buildStep2(cs),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 0: Patient Info
  Widget _buildStep0(ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Doctor info card
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.event_available_rounded, color: cs.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Book Your Visit', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('Select a treatment and enter details below.', style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Service selector
          Text('Select Treatment', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          ...List.generate(_services.length, (i) => _ServiceTile(
            service: _services[i],
            icon: _serviceIcons[i],
            color: _serviceColors[i],
            isSelected: _service == _services[i],
            onTap: () => setState(() => _service = _services[i]),
          )),
          const SizedBox(height: 18),

          Text('Patient Information', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(hintText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => Validators.requiredField(v, 'full name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: (v) => Validators.requiredField(v, 'phone number'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'Email (optional)', prefixIcon: Icon(Icons.mail_outline_rounded)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _professionController,
                  decoration: const InputDecoration(hintText: 'Profession (optional)', prefixIcon: Icon(Icons.work_outline_rounded)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Reason for visit *', prefixIcon: Padding(padding: EdgeInsets.only(bottom: 42), child: Icon(Icons.edit_note_rounded))),
                  validator: (v) => Validators.requiredField(v, 'visit reason'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Additional notes (optional)', prefixIcon: Padding(padding: EdgeInsets.only(bottom: 24), child: Icon(Icons.notes_rounded))),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _totalSessionsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Treatment Plan Total Sessions (Optional)',
                    prefixIcon: const Icon(Icons.playlist_add_check_rounded),
                    suffixIcon: PopupMenuButton<int?>(
                      icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                      onSelected: (val) {
                        setState(() {
                          _treatmentPlanTotalSessions = val;
                          _totalSessionsController.text = val == null ? '' : val.toString();
                          if (val != null) {
                            if (_sessionNumber == null || _sessionNumber == 0) {
                              _sessionNumber = 1;
                              _sessionNumberController.text = '1';
                            }
                          } else {
                            _sessionNumber = null;
                            _sessionNumberController.clear();
                          }
                        });
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: null, child: Text('None (Single Session)', style: GoogleFonts.poppins(fontSize: 13))),
                        PopupMenuItem(value: 6, child: Text('6 Sessions Plan', style: GoogleFonts.poppins(fontSize: 13))),
                        PopupMenuItem(value: 8, child: Text('8 Sessions Plan', style: GoogleFonts.poppins(fontSize: 13))),
                        PopupMenuItem(value: 12, child: Text('12 Sessions Plan', style: GoogleFonts.poppins(fontSize: 13))),
                      ],
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      final n = int.tryParse(v);
                      _treatmentPlanTotalSessions = n;
                      if (n != null && n > 0) {
                        if (_sessionNumber == null || _sessionNumber == 0) {
                          _sessionNumber = 1;
                          _sessionNumberController.text = '1';
                        }
                      } else {
                        _sessionNumber = null;
                        _sessionNumberController.clear();
                      }
                    });
                  },
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) return 'Must be a positive number';
                    return null;
                  },
                ),
                if (_treatmentPlanTotalSessions != null) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _sessionNumberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Session Number',
                      prefixIcon: Icon(Icons.pin_rounded),
                    ),
                    validator: (v) {
                      if (_treatmentPlanTotalSessions == null) return null;
                      if (v == null || v.isEmpty) return 'Required';
                      final n = int.tryParse(v);
                      if (n == null || n <= 0) return 'Must be a positive number';
                      if (n > _treatmentPlanTotalSessions!) return 'Cannot exceed total sessions';
                      return null;
                    },
                    onChanged: (v) {
                      _sessionNumber = int.tryParse(v);
                    },
                  ),
                ],
                const SizedBox(height: 14),
                // Appointment Duration Selector
                TextFormField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Appointment Duration (minutes)',
                    prefixIcon: const Icon(Icons.timer_outlined),
                    suffixIcon: PopupMenuButton<int>(
                      icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                      onSelected: (val) {
                        setState(() {
                          _durationMinutes = val;
                          _durationController.text = val.toString();
                        });
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 20, child: Text('20 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                        PopupMenuItem(value: 40, child: Text('40 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                        PopupMenuItem(value: 60, child: Text('60 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                        PopupMenuItem(value: 80, child: Text('80 minutes', style: GoogleFonts.poppins(fontSize: 13))),
                      ],
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Duration is required';
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) return 'Must be a positive number';
                    if (n > 240) return 'Cannot exceed 240 minutes';
                    return null;
                  },
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n > 0) {
                      setState(() => _durationMinutes = n);
                    }
                  },
                ),
                const SizedBox(height: 14),
                // Date of Birth picker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cake_rounded, color: cs.primary, size: 20),
                  ),
                  title: Text(
                    _selectedDob == null
                        ? 'Date of Birth (Optional)'
                        : 'DOB: ${DateFormat('d MMM y').format(_selectedDob!)}  •  Age: ${DateTime.now().year - _selectedDob!.year} yrs',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: _selectedDob == null ? FontWeight.w400 : FontWeight.w600,
                      color: _selectedDob == null ? cs.onSurface.withValues(alpha: 0.45) : cs.onSurface,
                    ),
                  ),
                  trailing: _selectedDob != null
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
                          onPressed: () => setState(() => _selectedDob = null),
                        )
                      : Icon(Icons.arrow_drop_down_rounded, color: cs.primary),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDob ?? DateTime(1990),
                      firstDate: DateTime(1920),
                      lastDate: DateTime.now(),
                      helpText: 'Select Patient Date of Birth',
                    );
                    if (picked != null) setState(() => _selectedDob = picked);
                  },
                ),
                const SizedBox(height: 4),
                const Divider(),
                const SizedBox(height: 4),

                // Posture Photo
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.photo_camera_rounded, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('Posture Photo (Optional)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
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
                          height: 160,
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
                                final picker = ImagePicker();
                                final img = await picker.pickImage(
                                  source: ImageSource.camera,
                                  imageQuality: 80,
                                );
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
                                final picker = ImagePicker();
                                final img = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 80,
                                );
                                if (img != null) setState(() => _posturalPhotoPath = img.path);
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(),
                const SizedBox(height: 4),

                SwitchListTile.adaptive(
                  value: _isEmergency,
                  onChanged: (v) => setState(() => _isEmergency = v),
                  title: Text('Emergency / High Priority', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('Mark this appointment as emergency', style: GoogleFonts.poppins(fontSize: 11)),
                  activeColor: const Color(0xFFEF4444),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                if (_canGoToStep1()) _goStep(1);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Choose Date & Time'),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Schedule
  Widget _buildStep1(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.calendar_month_rounded, color: cs.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Date & Time', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('Set precise appointment date and time.', style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        Text('Manual Date & Time Selection', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),
        PremiumCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.today_rounded, color: cs.primary),
                ),
                title: Text(
                  _selectedDate == null ? 'Select Date *' : DateFormat('EEEE, d MMMM y').format(_selectedDate!),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: _selectedDate == null ? FontWeight.w500 : FontWeight.w700,
                    color: _selectedDate == null ? cs.onSurface.withValues(alpha: 0.5) : cs.onSurface,
                  ),
                ),
                trailing: Icon(Icons.arrow_drop_down_circle_outlined, color: cs.primary),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) {
                    setState(() => _selectedDate = d);
                  }
                },
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.access_time_filled_rounded, color: cs.primary),
                ),
                title: Text(
                  _selectedSlot ?? 'Select Precise Time *',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: _selectedSlot == null ? FontWeight.w500 : FontWeight.w700,
                    color: _selectedSlot == null ? cs.onSurface.withValues(alpha: 0.5) : cs.onSurface,
                  ),
                ),
                trailing: Icon(Icons.arrow_drop_down_circle_outlined, color: cs.primary),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _selectedSlot != null
                        ? TimeOfDay.fromDateTime(DateFormat('hh:mm a').parse(_selectedSlot!))
                        : const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (t != null) {
                    final dt = DateTime(2020, 1, 1, t.hour, t.minute);
                    setState(() => _selectedSlot = DateFormat('hh:mm a').format(dt));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Quick Select Slots (Optional)',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedSlot != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _selectedSlot = null),
                child: Text('Clear time', style: GoogleFonts.poppins(fontSize: 12, color: Colors.redAccent)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
          ),
          itemCount: _slots.length,
          itemBuilder: (context, i) {
            final slot = _slots[i];
            final isSelected = _selectedSlot == slot;
            return GestureDetector(
              onTap: () => setState(() => _selectedSlot = slot),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3)),
                  boxShadow: isSelected ? [BoxShadow(color: cs.primary.withValues(alpha: 0.2), blurRadius: 8)] : [],
                ),
                child: Center(
                  child: Text(
                    slot,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goStep(0),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_selectedDate != null && _selectedSlot != null) ? () => _goStep(2) : null,
                child: const Text('Review Booking'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 2: Confirm
  Widget _buildStep2(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.statusConfirmedBg, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.check_circle_rounded, color: AppColors.statusConfirmed, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Review your booking', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Confirm details below', style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 14),
              _ConfirmRow(label: 'Patient', value: _nameController.text),
              _ConfirmRow(label: 'Phone', value: _phoneController.text),
              if (_emailController.text.isNotEmpty)
                _ConfirmRow(label: 'Email', value: _emailController.text),
              _ConfirmRow(label: 'Treatment', value: _service),
              if (_selectedDate != null)
                _ConfirmRow(label: 'Date', value: DateFormat('EEEE, d MMMM y').format(_selectedDate!)),
              if (_selectedSlot != null)
                _ConfirmRow(label: 'Time', value: _selectedSlot!),
              _ConfirmRow(label: 'Doctor', value: 'DR. BASHIR AHMAD'),
              if (_treatmentPlanTotalSessions != null)
                _ConfirmRow(
                  label: 'Treatment Plan',
                  value: 'Session ${_sessionNumber ?? 1} of $_treatmentPlanTotalSessions Sessions Plan',
                ),
              _ConfirmRow(label: 'Duration', value: '$_durationMinutes minutes'),
              if (_selectedDob != null)
                _ConfirmRow(
                  label: 'DOB / Age',
                  value: '${DateFormat('d MMM y').format(_selectedDob!)}  •  ${DateTime.now().year - _selectedDob!.year} yrs',
                ),
              if (_isEmergency)
                _ConfirmRow(label: 'Priority', value: 'EMERGENCY (Custom Time)'),
              if (_reasonController.text.isNotEmpty)
                _ConfirmRow(label: 'Reason', value: _reasonController.text),
              if (_posturalPhotoPath != null) ...[
                const SizedBox(height: 8),
                Text('Posture Photo', style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(_posturalPhotoPath!), height: 120, width: double.infinity, fit: BoxFit.cover),
                ),
              ],
              const SizedBox(height: 6),
              const Divider(),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusPendingBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.statusPending, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Appointment will be marked as Pending until confirmed by the clinic.', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.statusPending))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: () => _goStep(1), child: const Text('Back')),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitBooking,
                child: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Confirm Booking ✓'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Supporting widgets

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  static const _labels = ['Patient Info', 'Schedule', 'Confirm'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: List.generate(3, (i) {
          final isActive = i <= currentStep;
          final isCurrent = i == currentStep;
          return Expanded(
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: isCurrent ? 32 : 28,
                      height: isCurrent ? 32 : 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? cs.primary : cs.surface,
                        border: Border.all(color: isActive ? cs.primary : cs.outline.withValues(alpha: 0.3), width: 1.5),
                        boxShadow: isCurrent ? [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 10)] : [],
                      ),
                      child: Center(
                        child: isActive && i < currentStep
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                            : Text('${i + 1}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: isActive ? Colors.white : cs.onSurface.withValues(alpha: 0.4))),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_labels[i], style: GoogleFonts.poppins(fontSize: 10, fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400, color: isActive ? cs.primary : cs.onSurface.withValues(alpha: 0.4))),
                  ],
                ),
                if (i < 2)
                  Expanded(
                    child: Container(
                      height: 1.5,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: i < currentStep ? cs.primary : cs.outline.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.icon, required this.color, required this.isSelected, required this.onTap});
  final String service;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(service, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: isSelected ? color : Theme.of(context).colorScheme.onSurface)),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5)))),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
