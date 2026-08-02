import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/shared/widgets/app_shell_scaffold.dart';
import '../../features/shared/widgets/premium_card.dart';
import '../../models/appointment.dart';
import '../../utils/validators.dart';
import 'appointment_repository.dart';
import '../../theme/app_theme.dart';
import '../../services/repository_providers.dart';
import '../../services/notification_service.dart';
import '../utils/image_service.dart';

enum PaymentMode { online, cash }

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, this.initialData});
  final Map<String, dynamic>? initialData;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen>
    with SingleTickerProviderStateMixin {
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

  AppointmentRepository get _repository =>
      ref.read(appointmentRepositoryProvider);

  int _step = 0; // 0=info, 1=schedule, 2=confirm
  String _service = 'Gonstead Adjustment';
  DateTime? _selectedDate;
  String? _selectedSlot;
  bool _isSubmitting = false;
  bool _isEmergency = false;

  int? _treatmentPlanTotalSessions;
  int? _sessionNumber;
  int _durationMinutes = 40;

  // Payment Mode
  PaymentMode _paymentMode = PaymentMode.cash;

  static const Map<String, double> _servicePrices = {
    'Gonstead Adjustment': 5000.0,
    'Spinal Screening': 3000.0,
    'Posture Assessment': 2500.0,
    'Full Consultation': 8000.0,
    'Follow-up Visit': 4000.0,
  };

  double get _currentPrice => _servicePrices[_service] ?? 0.0;

  // New fields
  DateTime? _selectedDob;
  String? _posturalPhotoPath;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  // Time slots 9am–7pm every 30 min (customizable/overrideable on conflicts)
  static final List<String> _slots = [
    '09:00 AM',
    '09:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '12:00 PM',
    '12:30 PM',
    '01:00 PM',
    '01:30 PM',
    '02:00 PM',
    '02:30 PM',
    '03:00 PM',
    '03:30 PM',
    '04:00 PM',
    '04:30 PM',
    '05:00 PM',
    '05:30 PM',
    '06:00 PM',
    '06:30 PM',
  ];

  static const List<String> _services = [
    'Gonstead Adjustment',
    'Spinal Screening',
    'Posture Assessment',
    'Full Consultation',
    'Follow-up Visit',
  ];

  static const List<Color> _serviceColors = [
    Color(0xFF0A6BE8),
    Color(0xFF6366F1),
    Color(0xFF00A86B),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
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
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    if (widget.initialData != null) {
      _nameController.text =
          widget.initialData!['patientName']?.toString() ?? '';
      _phoneController.text =
          widget.initialData!['phoneNumber']?.toString() ?? '';
      _emailController.text = widget.initialData!['email']?.toString() ?? '';
      _professionController.text =
          widget.initialData!['patientProfession']?.toString() ?? '';
      _service =
          widget.initialData!['treatmentType']?.toString() ??
          'Gonstead Adjustment';
      _treatmentPlanTotalSessions =
          widget.initialData!['treatmentPlanTotalSessions'] as int?;
      if (_treatmentPlanTotalSessions != null) {
        _totalSessionsController.text = _treatmentPlanTotalSessions!.toString();
      }
      _sessionNumber = widget.initialData!['sessionNumber'] as int?;
      if (_sessionNumber != null) {
        _sessionNumberController.text = _sessionNumber!.toString();
      }
      _reasonController.text =
          widget.initialData!['visitReason']?.toString() ??
          'Next follow-up treatment session.';
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
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        hour,
        minute,
      );
      final formattedDate = DateFormat('EEE, d MMM').format(_selectedDate!);

      final appointments = await _repository.loadAppointments();

      // Check conflict: Active appointments that are NOT cancelled AND NOT rejected
      final activeAppointments = appointments
          .where(
            (a) =>
                a.status.toLowerCase() != 'cancelled' &&
                a.status.toLowerCase() != 'rejected' &&
                a.scheduledAt != null,
          )
          .toList();

      Appointment? conflict;
      for (final appt in activeAppointments) {
        final diff = scheduledDateTime
            .difference(appt.scheduledAt!)
            .inMinutes
            .abs();
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
            final diff = nextAvailable
                .difference(appt.scheduledAt!)
                .inMinutes
                .abs();
            final requiredGap = _durationMinutes;
            if (diff < requiredGap) {
              nextAvailable = appt.scheduledAt!.add(
                Duration(minutes: requiredGap),
              );
              hasConflict = true;
              break;
            }
          }
        }

        final suggestedDateText = DateFormat(
          'EEEE, d MMMM y',
        ).format(nextAvailable);
        final suggestedTimeText = DateFormat('hh:mm a').format(nextAvailable);

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Booking Conflict',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'This time slot conflicts with an existing appointment (enforcing $_durationMinutes-minute gap):\n\n'
                'Requested: $formattedDate at $_selectedSlot\n'
                'Next Free: $suggestedDateText at $suggestedTimeText\n\n'
                'Would you like to auto-adjust to the next available time?',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go back'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedDate = DateTime(
                        nextAvailable.year,
                        nextAvailable.month,
                        nextAvailable.day,
                      );
                      _selectedSlot = DateFormat(
                        'hh:mm a',
                      ).format(nextAvailable);
                    });
                  },
                  child: const Text('Auto-Adjust'),
                ),
              ],
            ),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      final newAppt = Appointment(
        id: const Uuid().v4(),
        patientName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        time: _selectedSlot!,
        scheduledAt: scheduledDateTime,
        treatmentType: _service,
        status: 'Pending',
        isEmergency: _isEmergency,
        visitReason: _reasonController.text.trim(),
        patientNote: _notesController.text.trim(),
        patientProfession: _professionController.text.trim(),
        treatmentPlanTotalSessions: _treatmentPlanTotalSessions,
        sessionNumber: _sessionNumber,
        durationMinutes: _durationMinutes,
        dateOfBirth: _selectedDob,
        posturalPhotoPath: _posturalPhotoPath ?? '',
        paymentMethod: _paymentMode == PaymentMode.online ? 'online' : 'cash',
        paymentStatus: 'pending',
        amount: _currentPrice,
        updatedAt: DateTime.now(),
      );

      // Save initial record to Firestore with 'pending' status
      final bool wasSynced = await _repository.saveAppointment(newAppt);

      if (!wasSynced) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Saved offline as unstable internet, will be booked once connected.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // Notify service to watch for restoration
        NotificationService().setOfflineBookingPending(true);
      }

      if (_paymentMode == PaymentMode.online) {
        // Initialize Online Payment via Service
        final payService = ref.read(paymentGatewayServiceProvider);
        try {
          final res = await payService.initializeSafepayTransaction(
            amount: _currentPrice,
            currency: 'PKR',
            customerEmail: _emailController.text.trim(),
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
          debugPrint('Online payment failed to init: $e');
        }
      }

      // Schedule local notifications
      try {
        await NotificationService().scheduleAppointmentReminders(newAppt);
      } catch (e) {
        debugPrint('Notification scheduling failed: $e');
      }

      _goStep(2);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppShellScaffold(
      title: 'Book Appointment',
      currentRoute: '/booking',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStepper(cs),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _fadeAnim,
              child: _step == 0
                  ? _buildPersonalInfoStep(cs)
                  : _step == 1
                  ? _buildSchedulingStep(cs)
                  : _buildSuccessStep(cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(ColorScheme cs) {
    return Row(
      children: [
        _stepCircle(0, 'Details', cs),
        _stepLine(cs),
        _stepCircle(1, 'Schedule', cs),
        _stepLine(cs),
        _stepCircle(2, 'Done', cs),
      ],
    );
  }

  Widget _stepCircle(int step, String label, ColorScheme cs) {
    final isActive = _step == step;
    final isDone = _step > step;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? AppColors.statusConfirmed
                : isActive
                ? cs.primary
                : cs.surfaceContainerHighest,
            border: isActive
                ? Border.all(color: cs.primary.withValues(alpha: 0.2), width: 4)
                : null,
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    (step + 1).toString(),
                    style: GoogleFonts.poppins(
                      color: isActive ? Colors.white : cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _stepLine(ColorScheme cs) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16),
        color: cs.surfaceContainerHighest,
      ),
    );
  }

  Widget _buildPersonalInfoStep(ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patient Information',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: 'e.g. 03xx-xxxxxxx',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Profession',
                    prefixIcon: Icon(Icons.work_outline_rounded),
                  ),
                  items:
                      [
                            'Engineer',
                            'Doctor',
                            'Teacher',
                            'Student',
                            'Office Worker',
                            'Driver',
                            'Laborer',
                            'Retired',
                            'Housewife',
                            'Businessman',
                            'Nurse',
                            'Salesperson',
                            'Accountant',
                            'Builder/Mason',
                            'Farmer',
                            'Unemployed',
                            'Self-employed',
                            'Artist',
                            'Software Developer',
                            'Security Guard',
                            'Police Officer',
                            'Soldier',
                            'Tailor',
                            'Shopkeeper',
                            'Chef',
                            'Other',
                          ]
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                  onChanged: (v) => _professionController.text = v ?? '',
                ),
                const SizedBox(height: 16),
                // DOB Picker
                InkWell(
                  onTap: () async {
                    final dt = await showDatePicker(
                      context: context,
                      initialDate:
                          _selectedDob ??
                          DateTime.now().subtract(
                            const Duration(days: 365 * 30),
                          ),
                      firstDate: DateTime(1920),
                      lastDate: DateTime.now(),
                    );
                    if (dt != null) setState(() => _selectedDob = dt);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date of Birth',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    child: Text(
                      _selectedDob == null
                          ? 'Select birthday'
                          : DateFormat('d MMM yyyy').format(_selectedDob!),
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Clinical Details',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _service,
                  decoration: const InputDecoration(
                    labelText: 'Service Type',
                    prefixIcon: Icon(Icons.medical_services_outlined),
                  ),
                  items: _services
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _service = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Visit',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                    hintText: 'e.g. Lower back pain, sciatica…',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Duration (min)',
                          prefixIcon: const Icon(Icons.timer_outlined),
                          suffixIcon: PopupMenuButton<int>(
                            icon: const Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 28,
                            ),
                            onSelected: (val) {
                              setState(() {
                                _durationMinutes = val;
                                _durationController.text = val.toString();
                              });
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 20,
                                child: Text(
                                  '20 minutes',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ),
                              PopupMenuItem(
                                value: 40,
                                child: Text(
                                  '40 minutes',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ),
                              PopupMenuItem(
                                value: 60,
                                child: Text(
                                  '60 minutes',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ),
                              PopupMenuItem(
                                value: 80,
                                child: Text(
                                  '80 minutes',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        onChanged: (val) {
                          _durationMinutes = int.tryParse(val) ?? 40;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          'Emergency',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Switch.adaptive(
                          value: _isEmergency,
                          activeColor: Colors.red,
                          onChanged: (v) => setState(() => _isEmergency = v),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Treatment Plan Helpers
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _totalSessionsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Plan Total Sessions',
                          hintText: 'e.g. 10',
                        ),
                        onChanged: (val) =>
                            _treatmentPlanTotalSessions = int.tryParse(val),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _sessionNumberController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Current Session #',
                          hintText: 'e.g. 1',
                        ),
                        onChanged: (val) => _sessionNumber = int.tryParse(val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Posture Photo Picker
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.photo_camera_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Initial Posture Photo (Optional)',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_posturalPhotoPath != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_posturalPhotoPath!),
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                ),
                                onPressed: () =>
                                    setState(() => _posturalPhotoPath = null),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.camera_alt_rounded),
                              label: const Text('Camera'),
                              onPressed: () async {
                                final img = await ImagePicker().pickImage(
                                  source: ImageSource.camera,
                                );
                                if (img != null) {
                                  final compressed =
                                      await ImageService.compressPostureImage(
                                        File(img.path),
                                      );
                                  setState(
                                    () => _posturalPhotoPath =
                                        compressed?.path ?? img.path,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.photo_library_rounded),
                              label: const Text('Gallery'),
                              onPressed: () async {
                                final img = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                );
                                if (img != null) {
                                  final compressed =
                                      await ImageService.compressPostureImage(
                                        File(img.path),
                                      );
                                  setState(
                                    () => _posturalPhotoPath =
                                        compressed?.path ?? img.path,
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                if (_canGoToStep1()) _goStep(1);
              },
              child: const Text('Continue to Scheduling'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulingStep(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => _goStep(0),
            ),
            Text(
              'Select Date & Time',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Available Dates',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _dateOptions.length,
            itemBuilder: (context, i) {
              final date = _dateOptions[i];
              final isSelected =
                  _selectedDate != null &&
                  _selectedDate!.day == date.day &&
                  _selectedDate!.month == date.month;
              return GestureDetector(
                onTap: () => setState(() => _selectedDate = date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 65,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? null
                        : Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: isSelected
                              ? Colors.white70
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        date.day.toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Available Slots',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
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
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? cs.primary : cs.outlineVariant,
                  ),
                ),
                child: Center(
                  child: Text(
                    slot,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? Colors.white : cs.onSurface,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        Text(
          'Payment Mode',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _paymentChoice(
                PaymentMode.cash,
                'Pay at Clinic',
                'Pay in-person (Cash/EasyPaisa)',
                Icons.payments_outlined,
                cs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _paymentChoice(
                PaymentMode.online,
                'Pay Online',
                'Secure checkout via Safepay',
                Icons.credit_card_rounded,
                cs,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitBooking,
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Confirm Appointment'),
          ),
        ),
      ],
    );
  }

  Widget _paymentChoice(
    PaymentMode mode,
    String title,
    String sub,
    IconData icon,
    ColorScheme cs,
  ) {
    final isSelected = _paymentMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _paymentMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withValues(alpha: 0.1) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? cs.primary : cs.onSurface,
              ),
            ),
            Text(
              sub,
              style: GoogleFonts.poppins(
                fontSize: 9,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessStep(ColorScheme cs) {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.statusConfirmed.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.statusConfirmed,
            size: 40,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Appointment Requested!',
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Your visit has been successfully booked. You will receive a notification reminder 1 hour before.',
          style: GoogleFonts.poppins(color: cs.onSurfaceVariant, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        PremiumCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _summaryRow('Patient', _nameController.text),
              const Divider(height: 24),
              _summaryRow(
                'Date',
                DateFormat('EEEE, d MMMM').format(_selectedDate!),
              ),
              const Divider(height: 24),
              _summaryRow('Time', _selectedSlot!),
              const Divider(height: 24),
              _summaryRow('Treatment', _service),
              const Divider(height: 24),
              _summaryRow(
                'Fee',
                'PKR ${NumberFormat('#,##0').format(_currentPrice)}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Back to Dashboard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  _nameController.clear();
                  _phoneController.clear();
                  _emailController.clear();
                  _notesController.clear();
                  _reasonController.clear();
                  _goStep(0);
                },
                child: const Text('Book Another'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
