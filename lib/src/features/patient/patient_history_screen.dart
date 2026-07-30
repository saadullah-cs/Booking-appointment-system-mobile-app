import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../models/appointment.dart';
import '../appointments/pdf_generator.dart';
import '../../services/repository_providers.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import '../../theme/app_theme.dart';

class UniquePatient {
  final String name;
  final String phone;
  final int visitCount;
  final DateTime? latestVisit;
  final String latestTreatment;

  UniquePatient({
    required this.name,
    required this.phone,
    required this.visitCount,
    required this.latestVisit,
    required this.latestTreatment,
  });
}

class PatientHistoryScreen extends ConsumerStatefulWidget {
  const PatientHistoryScreen({
    super.key,
    required this.patientName,
    required this.phoneNumber,
  });

  final String patientName;
  final String phoneNumber;

  @override
  ConsumerState<PatientHistoryScreen> createState() =>
      _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends ConsumerState<PatientHistoryScreen> {
  bool _isLoading = true;
  List<Appointment> _history = [];
  List<UniquePatient> _allPatients = [];
  String _searchQuery = '';
  String _selectedDuration = 'All';
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant PatientHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientName != widget.patientName ||
        oldWidget.phoneNumber != widget.phoneNumber) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final repo = ref.read(appointmentRepositoryProvider);
    final allApts = await repo.loadAppointments();

    if (widget.patientName.isEmpty) {
      // Load Patient Directory
      final Map<String, UniquePatient> uniquePatients = {};
      for (final a in allApts) {
        if (a.patientName.trim().isEmpty) continue;
        final key =
            '${a.patientName.trim().toLowerCase()}_${a.phoneNumber.trim().toLowerCase()}';
        final existing = uniquePatients[key];
        final date = a.scheduledAt;
        if (existing == null) {
          uniquePatients[key] = UniquePatient(
            name: a.patientName.trim(),
            phone: a.phoneNumber.trim(),
            visitCount: 1,
            latestVisit: date,
            latestTreatment: a.treatmentType,
          );
        } else {
          final isNewer =
              date != null &&
              (existing.latestVisit == null ||
                  date.isAfter(existing.latestVisit!));
          uniquePatients[key] = UniquePatient(
            name: existing.name,
            phone: existing.phone,
            visitCount: existing.visitCount + 1,
            latestVisit: isNewer ? date : existing.latestVisit,
            latestTreatment: isNewer
                ? a.treatmentType
                : existing.latestTreatment,
          );
        }
      }
      final sortedPatients = uniquePatients.values.toList()
        ..sort((a, b) {
          if (a.latestVisit == null && b.latestVisit == null) return 0;
          if (a.latestVisit == null) return 1;
          if (b.latestVisit == null) return -1;
          return b.latestVisit!.compareTo(a.latestVisit!);
        });
      if (!mounted) return;
      setState(() {
        _allPatients = sortedPatients;
        _isLoading = false;
      });
    } else {
      // Load specific patient history
      final filtered = allApts.where((a) {
        final nameMatch =
            a.patientName.toLowerCase().trim() ==
            widget.patientName.toLowerCase().trim();
        final phoneMatch =
            widget.phoneNumber.isNotEmpty &&
            a.phoneNumber.trim() == widget.phoneNumber.trim();
        return nameMatch || phoneMatch;
      }).toList();

      filtered.sort((a, b) {
        if (a.scheduledAt == null && b.scheduledAt == null) return 0;
        if (a.scheduledAt == null) return 1;
        if (b.scheduledAt == null) return -1;
        return b.scheduledAt!.compareTo(a.scheduledAt!);
      });

      if (!mounted) return;
      setState(() {
        _history = filtered;
        _isLoading = false;
      });
    }
  }

  Color _getPainColor(int score) {
    if (score <= 3) return Colors.green;
    if (score <= 6) return Colors.orange;
    return Colors.red;
  }

  Future<void> _printFullRecord() async {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No history records to print.')),
      );
      return;
    }
    try {
      final bytes = await generateAllSessionsReportPdf(_history);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: '${widget.patientName}_Comprehensive_Report',
      );
    } catch (e) {
      debugPrint('Error printing clinical history: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate print: $e')));
      }
    }
  }

  bool _matchesDuration(DateTime? date) {
    if (_selectedDuration == 'All') return true;
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recordDate = DateTime(date.year, date.month, date.day);

    if (_selectedDuration == 'Today') {
      return recordDate.isAtSameMomentAs(today);
    }
    if (_selectedDuration == 'Yesterday') {
      final yesterday = today.subtract(const Duration(days: 1));
      return recordDate.isAtSameMomentAs(yesterday);
    }
    final diff = now.difference(date).abs();
    if (_selectedDuration == '7 Days') return diff.inDays <= 7;
    if (_selectedDuration == '30 Days') return diff.inDays <= 30;
    if (_selectedDuration == '6 Months') return diff.inDays <= 180;
    if (_selectedDuration == '1 Year') return diff.inDays <= 365;
    if (_selectedDuration == 'Custom' && _customDateRange != null) {
      return (date.isAfter(_customDateRange!.start) ||
              date.isAtSameMomentAs(_customDateRange!.start)) &&
          (date.isBefore(_customDateRange!.end.add(const Duration(days: 1))) ||
              date.isAtSameMomentAs(_customDateRange!.end));
    }
    return true;
  }

  Widget _buildDurationFilterChips(ColorScheme cs) {
    final options = [
      'All',
      'Today',
      'Yesterday',
      '7 Days',
      '30 Days',
      '6 Months',
      '1 Year',
      'Custom',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final isSelected = _selectedDuration == opt;
          String chipText = opt;
          if (opt == 'Custom' && _customDateRange != null) {
            chipText =
                '${DateFormat('d MMM').format(_customDateRange!.start)} - ${DateFormat('d MMM').format(_customDateRange!.end)}';
          }
          return GestureDetector(
            onTap: () async {
              if (opt == 'Custom') {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(
                    const Duration(days: 365 * 5),
                  ),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: _customDateRange,
                );
                if (range != null) {
                  setState(() {
                    _selectedDuration = 'Custom';
                    _customDateRange = range;
                  });
                }
              } else {
                setState(() {
                  _selectedDuration = opt;
                  _customDateRange = null;
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : cs.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                chipText,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.patientName.isEmpty) {
      // Build Directory View
      final directoryFiltered = _allPatients.where((p) {
        if (!_matchesDuration(p.latestVisit)) return false;
        if (_searchQuery.isEmpty) return true;
        final q = _searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(q) ||
            p.phone.toLowerCase().contains(q);
      }).toList();

      return AppShellScaffold(
        title: 'Patient Directory',
        currentRoute: '/patient-history',
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: cs.primary))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Search patients and access their medical timelines.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: const InputDecoration(
                        hintText: 'Search patients by name or phone...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDurationFilterChips(cs),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'All Registered Patients',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${directoryFiltered.length} matched',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: directoryFiltered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_outline_rounded,
                                    size: 48,
                                    color: cs.onSurface.withValues(alpha: 0.25),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No patients found',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface.withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: directoryFiltered.length,
                              itemBuilder: (context, index) {
                                final p = directoryFiltered[index];
                                final dateStr = p.latestVisit != null
                                    ? DateFormat(
                                        'd MMM y',
                                      ).format(p.latestVisit!)
                                    : 'N/A';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10.0),
                                  child: PremiumCard(
                                    padding: EdgeInsets.zero,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        context.push(
                                          '/patient-history?name=${Uri.encodeComponent(p.name)}&phone=${Uri.encodeComponent(p.phone)}',
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor: cs.primary
                                                  .withValues(alpha: 0.1),
                                              child: Text(
                                                p.name.isNotEmpty
                                                    ? p.name[0].toUpperCase()
                                                    : '?',
                                                style: GoogleFonts.poppins(
                                                  fontWeight: FontWeight.w700,
                                                  color: cs.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    p.name,
                                                    style: GoogleFonts.poppins(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  if (p.phone.isNotEmpty)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.phone_outlined,
                                                          size: 11,
                                                          color: cs.onSurface
                                                              .withValues(alpha: 0.5),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          p.phone,
                                                          style:
                                                              GoogleFonts.poppins(
                                                                fontSize: 11,
                                                                color: cs
                                                                    .onSurface
                                                                    .withValues(
                                                                      alpha: 0.6,
                                                                    ),
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  Text(
                                                    'Latest: ${p.latestTreatment} • $dateStr',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11,
                                                      color: cs.onSurface
                                                          .withValues(alpha: 0.45),
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: cs.primary
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${p.visitCount} ${p.visitCount == 1 ? "visit" : "visits"}',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 16,
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
                            ),
                    ),
                  ],
                ),
              ),
      );
    }

    // Build Specific Patient Timeline View
    final displayHistory = _history.where((a) {
      if (!_matchesDuration(a.scheduledAt)) return false;
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return a.treatmentType.toLowerCase().contains(query) ||
          a.patientNote.toLowerCase().contains(query) ||
          a.adjustedSegments.toLowerCase().contains(query) ||
          a.status.toLowerCase().contains(query);
    }).toList();

    // Stats
    final totalVisits = _history.length;
    final completed = _history
        .where((a) => a.status.toLowerCase() == 'completed')
        .length;
    final adjustments = _history
        .where((a) => a.adjustedSegments.isNotEmpty)
        .length;

    return AppShellScaffold(
      title: 'Patient History',
      currentRoute: '/patient-history',
      actions: [
        IconButton(
          icon: const Icon(Icons.print_rounded),
          onPressed: _printFullRecord,
          tooltip: 'Print Comprehensive Clinical Record',
        ),
      ],
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Patient Banner Info
                PremiumCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: cs.primary.withValues(alpha: 0.1),
                            child: Text(
                              widget.patientName.isNotEmpty
                                  ? widget.patientName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.patientName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.phoneNumber.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_outlined,
                                        size: 13,
                                        color: cs.onSurface.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          widget.phoneNumber,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.65,
                                            ),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _printFullRecord,
                              icon: const Icon(Icons.print_rounded, size: 16),
                              label: const Text('Print Record'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.go('/patient-history'),
                              icon: const Icon(
                                Icons.people_alt_rounded,
                                size: 16,
                              ),
                              label: const Text('Directory'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Quick Statistics Banner
                Row(
                  children: [
                    _StatBox(
                      label: 'Total Visits',
                      value: totalVisits.toString(),
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    _StatBox(
                      label: 'Completed',
                      value: completed.toString(),
                      color: AppColors.statusConfirmed,
                    ),
                    const SizedBox(width: 10),
                    _StatBox(
                      label: 'Adjustments',
                      value: adjustments.toString(),
                      color: const Color(0xFF8B5CF6),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Search Bar & Filter chips
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Filter timeline by segment, notes, treatment...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDurationFilterChips(cs),
                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Clinical Timeline',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${displayHistory.length} Sessions',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (displayHistory.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.history_toggle_off_rounded,
                            size: 48,
                            color: cs.onSurface.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No timeline entries match filters',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayHistory.length,
                    itemBuilder: (context, index) {
                      final apt = displayHistory[index];
                      final dateStr = apt.scheduledAt != null
                          ? DateFormat(
                              'EEEE, d MMM y  •  hh:mm a',
                            ).format(apt.scheduledAt!)
                          : apt.time;
                      final isLast = index == displayHistory.length - 1;
                      final sColor = statusColor(apt.status);

                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Timeline dot & line
                            Column(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: sColor,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: sColor.withValues(alpha: 0.3),
                                        blurRadius: 4,
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
                                  const SizedBox(height: 20),
                              ],
                            ),
                            const SizedBox(width: 14),
                            // Content Card
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 20.0),
                                child: PremiumCard(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              dateStr,
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                                color: cs.primary,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusBgColor(apt.status),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              apt.status,
                                              style: GoogleFonts.poppins(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: sColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        apt.treatmentType,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const Divider(height: 18),

                                      // Vitals Row
                                      if (apt.pulseRate != null ||
                                          apt.bloodPressure.isNotEmpty ||
                                          apt.painLevel != null) ...[
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 6,
                                          children: [
                                            if (apt.pulseRate != null)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.favorite_rounded,
                                                    size: 14,
                                                    color: Colors.redAccent,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${apt.pulseRate} bpm',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (apt.bloodPressure.isNotEmpty)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.speed_rounded,
                                                    size: 14,
                                                    color: Colors.blueAccent,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    apt.bloodPressure,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            if (apt.painLevel != null)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.sick_outlined,
                                                    size: 14,
                                                    color: _getPainColor(
                                                      apt.painLevel!,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'VAS: ${apt.painLevel}/10',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _getPainColor(
                                                        apt.painLevel!,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                      ],

                                      // Adjustments
                                      if (apt.adjustedSegments.isNotEmpty) ...[
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.accessibility_new_rounded,
                                              size: 15,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: RichText(
                                                text: TextSpan(
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    color: cs.onSurface,
                                                  ),
                                                  children: [
                                                    TextSpan(
                                                      text: 'Adjustments: ',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                    TextSpan(
                                                      text:
                                                          apt.adjustedSegments,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                      ],

                                      // Exercises
                                      if (apt
                                          .prescribedExercises
                                          .isNotEmpty) ...[
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.directions_run_rounded,
                                              size: 15,
                                              color: cs.onSurface.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: RichText(
                                                text: TextSpan(
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    color: cs.onSurface,
                                                  ),
                                                  children: [
                                                    TextSpan(
                                                      text: 'Exercises: ',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                    TextSpan(
                                                      text: apt
                                                          .prescribedExercises,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                      ],

                                      // Clinical Notes
                                      if (apt.patientNote.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.04,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Clinical Note:',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.5),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                apt.patientNote,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                      ],

                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () => context
                                              .push('/appointment/${apt.id}')
                                              .then((_) => _loadData()),
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'View Full Session',
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
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
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
