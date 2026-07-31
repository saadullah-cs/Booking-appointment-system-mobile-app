import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../models/appointment.dart';
import '../../../theme/app_theme.dart';
import '../../shared/widgets/premium_card.dart';

class VisualCalendarWidget extends StatefulWidget {
  final List<Appointment> appointments;
  final Function(Appointment appointment)? onAppointmentTap;
  final Function(DateTime selectedTime)? onEmptySlotTap;

  const VisualCalendarWidget({
    super.key,
    required this.appointments,
    this.onAppointmentTap,
    this.onEmptySlotTap,
  });

  @override
  State<VisualCalendarWidget> createState() => _VisualCalendarWidgetState();
}

class _VisualCalendarWidgetState extends State<VisualCalendarWidget> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  // Generate 14 days around selected date for date strip
  List<DateTime> get _dateStripDays {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 3));
    return List.generate(14, (i) => start.add(Duration(days: i)));
  }

  // Clinic operating hours (8 AM to 7 PM)
  List<int> get _operatingHours => List.generate(12, (i) => 8 + i);

  // Get appointments for selected date
  List<Appointment> get _appointmentsForSelectedDate {
    final selectedStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    return widget.appointments.where((apt) {
      if (apt.scheduledAt == null) return false;
      return DateFormat('yyyy-MM-dd').format(apt.scheduledAt!.toLocal()) ==
          selectedStr;
    }).toList();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return AppColors.statusConfirmed;
      case 'pending':
        return AppColors.statusPending;
      case 'completed':
        return Colors.blueAccent;
      case 'cancelled':
        return Colors.redAccent;
      default:
        return AppColors.primary;
    }
  }

  Color _getStatusBg(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return AppColors.statusConfirmedBg;
      case 'pending':
        return AppColors.statusPendingBg;
      case 'completed':
        return Colors.blue.withValues(alpha: 0.1);
      case 'cancelled':
        return Colors.red.withValues(alpha: 0.1);
      default:
        return AppColors.primary.withValues(alpha: 0.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dayAppointments = _appointmentsForSelectedDate;

    return Column(
      children: [
        // Date Strip Header Card
        PremiumCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            children: [
              // Month Year Title & Today Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMMM yyyy').format(_selectedDate),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _selectedDate = DateTime.now());
                    },
                    icon: const Icon(Icons.today_rounded, size: 16),
                    label: Text(
                      'Today',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Horizontal Date Strip
              SizedBox(
                height: 72,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _dateStripDays.length,
                  itemBuilder: (context, index) {
                    final day = _dateStripDays[index];
                    final isSelected = DateFormat('yyyy-MM-dd').format(day) ==
                        DateFormat('yyyy-MM-dd').format(_selectedDate);
                    final isToday = DateFormat('yyyy-MM-dd').format(day) ==
                        DateFormat('yyyy-MM-dd').format(DateTime.now());

                    // Count appointments on this day
                    final dayStr = DateFormat('yyyy-MM-dd').format(day);
                    final hasApt = widget.appointments.any((a) =>
                        a.scheduledAt != null &&
                        DateFormat('yyyy-MM-dd')
                                .format(a.scheduledAt!.toLocal()) ==
                            dayStr);

                    return GestureDetector(
                      onTap: () => setState(() => _selectedDate = day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 54,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : (isToday
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : cs.surface),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : (isToday
                                    ? cs.primary.withValues(alpha: 0.4)
                                    : cs.outline.withValues(alpha: 0.12)),
                            width: isSelected || isToday ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('EEE').format(day).toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : cs.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('d').format(day),
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? Colors.white
                                    : cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasApt
                                    ? (isSelected ? Colors.white : cs.primary)
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Selected Day Summary Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(_selectedDate),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${dayAppointments.length} Appts Scheduled',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Hourly Schedule Timeline Grid
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _operatingHours.length,
          itemBuilder: (context, index) {
            final hour = _operatingHours[index];
            final hourFormatted =
                DateFormat('hh:00 a').format(DateTime(2026, 1, 1, hour));

            // Find appointments in this 1-hour block
            final hourApts = dayAppointments.where((apt) {
              if (apt.scheduledAt == null) return false;
              return apt.scheduledAt!.toLocal().hour == hour;
            }).toList();

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time Label (Left Column)
                  SizedBox(
                    width: 65,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        hourFormatted,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),

                  // Schedule Content Card / Slot (Right Column)
                  Expanded(
                    child: hourApts.isNotEmpty
                        ? Column(
                            children: hourApts.map((apt) {
                              final statusColor = _getStatusColor(apt.status);
                              final statusBg = _getStatusBg(apt.status);

                              return GestureDetector(
                                onTap: () {
                                  if (widget.onAppointmentTap != null) {
                                    widget.onAppointmentTap!(apt);
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: statusColor.withValues(alpha: 0.3),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    apt.patientName,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: cs.onSurface,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    apt.status.toUpperCase(),
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.healing_rounded,
                                                  size: 13,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.6),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  apt.treatmentType,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 11.5,
                                                    color: cs.onSurface
                                                        .withValues(
                                                            alpha: 0.65),
                                                  ),
                                                ),
                                                if (apt.scheduledAt !=
                                                    null) ...[
                                                  const SizedBox(width: 10),
                                                  Icon(
                                                    Icons.access_time_rounded,
                                                    size: 13,
                                                    color: cs.onSurface
                                                        .withValues(
                                                            alpha: 0.6),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    DateFormat('hh:mm a')
                                                        .format(apt.scheduledAt!
                                                            .toLocal()),
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          )
                        : GestureDetector(
                            onTap: () {
                              final slotTime = DateTime(
                                _selectedDate.year,
                                _selectedDate.month,
                                _selectedDate.day,
                                hour,
                              );
                              if (widget.onEmptySlotTap != null) {
                                widget.onEmptySlotTap!(slotTime);
                              } else {
                                context.push('/booking');
                              }
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.1),
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 16,
                                    color: cs.primary.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Available • Tap to book slot',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
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
    );
  }
}
