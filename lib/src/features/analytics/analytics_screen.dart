import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/appointment.dart';
import '../appointments/appointment_repository.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repository_providers.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  AppointmentRepository get _repository =>
      ref.read(appointmentRepositoryProvider);
  List<Appointment> _appointments = [];
  bool _isLoading = false;
  int _selectedFilter = 1; // default: weekly
  late TabController _tabController;

  static const _filterLabels = ['Today', 'Week', 'Month', 'Year'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _filterLabels.length,
      vsync: this,
      initialIndex: _selectedFilter,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedFilter = _tabController.index);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apts = await _repository.loadAppointments();
    if (!mounted) return;
    setState(() {
      _appointments = apts;
      _isLoading = false;
    });
  }

  List<Appointment> _filtered(DateTime now) {
    return _appointments.where((a) {
      final d = a.scheduledAt ?? _parseDate(a.time);
      if (d == null) return false;
      switch (_selectedFilter) {
        case 0:
          return d.year == now.year && d.month == now.month && d.day == now.day;
        case 1:
          final start = now.subtract(Duration(days: now.weekday - 1));
          return !d.isBefore(DateTime(start.year, start.month, start.day)) &&
              d.isBefore(start.add(const Duration(days: 7)));
        case 2:
          return d.year == now.year && d.month == now.month;
        case 3:
          return d.year == now.year;
        default:
          return true;
      }
    }).toList();
  }

  DateTime? _parseDate(String t) {
    try {
      return DateFormat('EEE, d MMM').parse(t.split('•').first.trim());
    } catch (_) {
      return null;
    }
  }

  List<_BarData> _buildBarData() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final count = _appointments.where((a) {
        final d = a.scheduledAt ?? _parseDate(a.time);
        return d != null &&
            d.year == day.year &&
            d.month == day.month &&
            d.day == day.day;
      }).length;
      return _BarData(label: DateFormat('E').format(day), value: count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final filtered = _filtered(now);
    final total = filtered.length;
    final confirmed = filtered
        .where((a) => a.status.toLowerCase() == 'confirmed')
        .length;
    final pending = filtered
        .where((a) => a.status.toLowerCase() == 'pending')
        .length;
    final cancelled = filtered
        .where((a) => a.status.toLowerCase() == 'cancelled')
        .length;
    final completed = filtered
        .where((a) => a.status.toLowerCase() == 'completed')
        .length;
    final cs = Theme.of(context).colorScheme;

    final width = MediaQuery.of(context).size.width;
    final isWide = width > 750;

    Widget filterTabsWidget() {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
        ),
        child: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w400,
            fontSize: 13,
          ),
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
          indicator: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          tabs: _filterLabels.map((l) => Tab(text: l)).toList(),
        ),
      );
    }

    Widget statsGridWidget() {
      return Column(
        children: [
          Row(
            children: [
              _StatBox(
                label: 'Total',
                value: total,
                color: cs.primary,
                icon: Icons.event_note_rounded,
              ),
              const SizedBox(width: 10),
              _StatBox(
                label: 'Confirmed',
                value: confirmed,
                color: AppColors.statusConfirmed,
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatBox(
                label: 'Pending',
                value: pending,
                color: AppColors.statusPending,
                icon: Icons.hourglass_top_rounded,
              ),
              const SizedBox(width: 10),
              _StatBox(
                label: 'Cancelled',
                value: cancelled,
                color: AppColors.statusCancelled,
                icon: Icons.cancel_outlined,
              ),
            ],
          ),
        ],
      );
    }

    Widget chartWidget() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 Days',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: _BarChart(data: _buildBarData()),
          ),
        ],
      );
    }

    Widget breakdownWidget() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status Breakdown',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _StatusBar(
                  label: 'Confirmed',
                  count: confirmed,
                  total: total,
                  color: AppColors.statusConfirmed,
                ),
                const SizedBox(height: 10),
                _StatusBar(
                  label: 'Pending',
                  count: pending,
                  total: total,
                  color: AppColors.statusPending,
                ),
                const SizedBox(height: 10),
                _StatusBar(
                  label: 'Completed',
                  count: completed,
                  total: total,
                  color: AppColors.statusCompleted,
                ),
                const SizedBox(height: 10),
                _StatusBar(
                  label: 'Cancelled',
                  count: cancelled,
                  total: total,
                  color: AppColors.statusCancelled,
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget recentListWidget() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent in Range',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            PremiumCard(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No appointments in this period.',
                  style: GoogleFonts.poppins(
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            ...filtered
                .take(8)
                .map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PremiumCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: cs.primary.withValues(alpha: 0.1),
                            child: Text(
                              a.patientName.isNotEmpty
                                  ? a.patientName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.poppins(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.patientName,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${a.time}  •  ${a.treatmentType}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    color: cs.onSurface.withValues(alpha: 0.55),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBgColor(a.status),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              a.status,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor(a.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      );
    }

    return AppShellScaffold(
      title: 'Analytics',
      currentRoute: '/analytics',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                children: [
                  isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  filterTabsWidget(),
                                  const SizedBox(height: 18),
                                  statsGridWidget(),
                                  const SizedBox(height: 18),
                                  breakdownWidget(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  chartWidget(),
                                  const SizedBox(height: 18),
                                  recentListWidget(),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            filterTabsWidget(),
                            const SizedBox(height: 16),
                            statsGridWidget(),
                            const SizedBox(height: 18),
                            chartWidget(),
                            const SizedBox(height: 18),
                            breakdownWidget(),
                            const SizedBox(height: 18),
                            recentListWidget(),
                          ],
                        ),
                ],
              ),
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
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

class _BarData {
  const _BarData({required this.label, required this.value});
  final String label;
  final int value;
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.data});
  final List<_BarData> data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final max = data.fold<int>(0, (m, d) => d.value > m ? d.value : m);
    final safeMax = max == 0 ? 1 : max;

    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data
            .map(
              (d) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (d.value > 0)
                        Text(
                          '${d.value}',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        height: (d.value / safeMax) * 90 + 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              cs.primary,
                              cs.primary.withValues(alpha: 0.5),
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        d.label,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 9,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$count',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
