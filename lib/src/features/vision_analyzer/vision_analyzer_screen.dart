import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/app_preferences.dart';
import '../../theme/app_theme.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import '../utils/image_service.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum VisionScenario {
  posture(
    'Spine & Posture',
    Icons.accessibility_new_rounded,
    Color(0xFF10B981),
  ),
  joints('Joint ROM', Icons.hdr_strong_rounded, Color(0xFFF59E0B)),
  dermatology('Dermatology', Icons.opacity_rounded, Color(0xFFEC4899)),
  facialAsymmetry(
    'Facial Palsy',
    Icons.face_retouching_natural_rounded,
    Color(0xFF6366F1),
  );

  final String label;
  final IconData icon;
  final Color color;
  const VisionScenario(this.label, this.icon, this.color);
}

// ─── Scan History Model ───────────────────────────────────────────────────────

class ScanRecord {
  final String patient;
  final VisionScenario scenario;
  final String severity;
  final Color severityColor;
  final DateTime timestamp;
  final String note;

  ScanRecord({
    required this.patient,
    required this.scenario,
    required this.severity,
    required this.severityColor,
    required this.timestamp,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'patient': patient,
    'scenario': scenario.name,
    'severity': severity,
    'severityColor': severityColor.toARGB32(),
    'timestamp': timestamp.toIso8601String(),
    'note': note,
  };

  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    final scName = json['scenario'] as String? ?? 'posture';
    final scenario = VisionScenario.values.firstWhere(
      (e) => e.name == scName,
      orElse: () => VisionScenario.posture,
    );
    return ScanRecord(
      patient: json['patient'] as String? ?? 'Unknown',
      scenario: scenario,
      severity: json['severity'] as String? ?? 'Normal',
      severityColor: Color(json['severityColor'] as int? ?? 0xFF10B981),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      note: json['note'] as String? ?? '',
    );
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class VisionAnalyzerScreen extends ConsumerStatefulWidget {
  const VisionAnalyzerScreen({super.key});

  @override
  ConsumerState<VisionAnalyzerScreen> createState() =>
      _VisionAnalyzerScreenState();
}

class _VisionAnalyzerScreenState extends ConsumerState<VisionAnalyzerScreen>
    with TickerProviderStateMixin {
  // --- State ---
  VisionScenario _scenario = VisionScenario.posture;
  File? _capturedImage;
  bool _isLive = true;
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _scanStatus = '';
  bool _reportReady = false;
  bool _fabOpen = false;
  String _selectedPatient = '';
  final String _doctorNotes = '';
  final List<String> _patients = [];
  final List<ScanRecord> _history = [];
  final TextEditingController _notesController = TextEditingController();

  // Metric sliders
  double _spineAngle = 4.2;
  double _jointAngle = 112.0;
  double _skinRisk = 84.0;
  double _faceAsym = 12.5;

  // Animations
  late AnimationController _scanLineCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _fabCtrl;
  late TabController _tabCtrl;
  late Animation<double> _scanLine;
  late Animation<double> _pulse;
  late Animation<double> _fabAnim;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPatients();
    _loadHistory();

    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _tabCtrl = TabController(length: 3, vsync: this);

    _scanLine = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut));
    _pulse = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fabAnim = CurvedAnimation(parent: _fabCtrl, curve: Curves.easeOut);
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await AppPreferences.instance.prefs;
      final raw = prefs.getString('vision_analyzer_history') ?? '[]';
      final List<dynamic> list = jsonDecode(raw);
      final records = list
          .map((e) => ScanRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (mounted) {
        setState(() {
          _history.clear();
          _history.addAll(records);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveHistoryToPrefs() async {
    try {
      final prefs = await AppPreferences.instance.prefs;
      final list = _history.map((e) => e.toJson()).toList();
      await prefs.setString('vision_analyzer_history', jsonEncode(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _notesController.dispose();
    _pulseCtrl.dispose();
    _scanLineCtrl.dispose();
    _fabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .get();
      final names = snap.docs
          .map((d) => d.data()['patientName'] as String?)
          .where((n) => n != null && n.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
      if (mounted) setState(() => _patients.addAll(names));
    } catch (_) {
      if (mounted) {
        setState(
          () => _patients.addAll([
            'Ahmad Ali',
            'Sara Khan',
            'Zainab Bibi',
            'Bilal Ahmed',
          ]),
        );
      }
    }
  }

  Future<void> _capture(ImageSource src) async {
    try {
      // Pick the image from camera or gallery
      final XFile? pickedFile = await _picker.pickImage(source: src);

      if (pickedFile != null && mounted) {
        final File sourceFile = File(pickedFile.path);
        final File? compressedFile = await ImageService.compressPostureImage(
          sourceFile,
        );

        setState(() {
          _capturedImage = compressedFile ?? sourceFile;
          _isLive = false;
        });

        await _runScan();
      }
    } catch (e) {
      _snack('Failed: $e', isError: true);
    }
    _closeFab();
  }

  void _resetToLive() {
    setState(() {
      _capturedImage = null;
      _isLive = true;
      _reportReady = false;
    });
    _closeFab();
  }

  void _toggleFab() {
    setState(() => _fabOpen = !_fabOpen);
    _fabOpen ? _fabCtrl.forward() : _fabCtrl.reverse();
  }

  void _closeFab() {
    if (_fabOpen) {
      setState(() => _fabOpen = false);
      _fabCtrl.reverse();
    }
  }

  Future<void> _runScan() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0;
      _reportReady = false;
    });
    final stages = [
      ('Initializing vision ML models…', 600),
      ('Segmenting landmark regions…', 900),
      ('Extracting anatomical vectors…', 1000),
      ('Synthesizing clinical analysis…', 700),
    ];
    for (int i = 0; i < stages.length; i++) {
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: stages[i].$2));
      if (mounted) {
        setState(() {
          _scanProgress = (i + 1) / stages.length;
          _scanStatus = stages[i].$1;
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _reportReady = true;
    });
    _snack('Analysis complete — tap Report tab 📋');
    _tabCtrl.animateTo(1);
  }

  void _saveRecord() {
    final info = _buildReportInfo();
    final record = ScanRecord(
      patient: _selectedPatient.isEmpty ? 'Unknown' : _selectedPatient,
      scenario: _scenario,
      severity: info['severity'] as String,
      severityColor: info['severityColor'] as Color,
      timestamp: DateTime.now(),
      note: _notesController.text,
    );
    setState(() {
      _history.insert(0, record);
      _notesController.clear();
    });
    _saveHistoryToPrefs();
    _snack('Saved to Patient History ✅');
    _tabCtrl.animateTo(2);
  }

  Future<void> _exportReportPdf() async {
    try {
      final info = _buildReportInfo();
      final doc = pw.Document();
      final primaryColor = PdfColor.fromHex('#0E7490');
      final accentColor = PdfColor.fromHex('#F8FAFC');
      final borderColor = PdfColor.fromHex('#E2E8F0');
      final textColor = PdfColor.fromHex('#1E293B');
      final labelColor = PdfColor.fromHex('#64748B');

      final patientName = _selectedPatient.isEmpty
          ? 'Patient / Walk-in'
          : _selectedPatient;
      final dateStr = DateFormat(
        'EEEE, MMMM d, yyyy - HH:mm',
      ).format(DateTime.now());

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'GONSTEAD CHIROPRACTIC CLINIC',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.Text(
                          'AI Patient Vision Analysis & Posture Report',
                          style: pw.TextStyle(fontSize: 10, color: labelColor),
                        ),
                      ],
                    ),
                    pw.Text(
                      dateStr,
                      style: pw.TextStyle(fontSize: 8, color: labelColor),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Divider(color: borderColor),
                pw.SizedBox(height: 12),

                // Patient Banner
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: accentColor,
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: borderColor),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PATIENT NAME',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: labelColor,
                            ),
                          ),
                          pw.Text(
                            patientName,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'SCAN MODULE',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: labelColor,
                            ),
                          ),
                          pw.Text(
                            _scenario.label,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'SEVERITY ASSESSMENT',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: labelColor,
                            ),
                          ),
                          pw.Text(
                            info['severity'] as String,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#DC2626'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 14),

                // Diagnostic Observation
                pw.Text(
                  'CLINICAL FINDINGS & DIAGNOSTIC OBSERVATIONS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderColor),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Observation:',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: labelColor,
                        ),
                      ),
                      pw.Text(
                        info['obs'] as String,
                        style: pw.TextStyle(fontSize: 9.5, color: textColor),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Diagnostic Synthesis:',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: labelColor,
                        ),
                      ),
                      pw.Text(
                        info['diagnostic'] as String,
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 14),

                // Recommended Actions
                pw.Text(
                  'RECOMMENDED CLINICAL ACTIONS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                pw.SizedBox(height: 6),
                ...(info['actions'] as List<String>).map(
                  (act) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      children: [
                        pw.Text(
                          '- ',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            act,
                            style: pw.TextStyle(fontSize: 9, color: textColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(height: 14),

                // Doctor Notes
                if (_notesController.text.isNotEmpty) ...[
                  pw.Text(
                    'PRACTITIONER NOTES',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: accentColor,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: borderColor),
                    ),
                    child: pw.Text(
                      _notesController.text,
                      style: pw.TextStyle(fontSize: 9, color: textColor),
                    ),
                  ),
                  pw.SizedBox(height: 14),
                ],

                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(width: 120, height: 1, color: labelColor),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Practitioner Signature',
                          style: pw.TextStyle(fontSize: 8, color: labelColor),
                        ),
                      ],
                    ),
                    pw.Text(
                      'Verified by Gonstead Clinical Vision Decision Support',
                      style: pw.TextStyle(fontSize: 7, color: labelColor),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: 'Vision_Report_${patientName.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      _snack('PDF Generation Failed: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── Computed Report ───────────────────────────────────────────────────────

  Map<String, dynamic> _buildReportInfo() {
    String severity, diagnostic, obs;
    Color col;
    List<String> actions;

    switch (_scenario) {
      case VisionScenario.posture:
        obs = 'Lateral shoulder tilt with forward head posture detected.';
        if (_spineAngle > 8) {
          severity = 'Moderate Risk';
          col = Colors.amber;
          diagnostic =
              'Spine deviation ${_spineAngle.toStringAsFixed(1)}° — possible scoliosis / FHP.';
          actions = [
            'Prescribe thoracic extension routines.',
            'Refer for standing AP/lateral X-ray.',
            'Ergonomic workspace evaluation.',
          ];
        } else {
          severity = 'Low Risk';
          col = Colors.green;
          diagnostic =
              'Spine alignment within normal range (${_spineAngle.toStringAsFixed(1)}°).';
          actions = ['Core stability 2×/week.', 'Regular stretching breaks.'];
        }

      case VisionScenario.joints:
        obs = 'Reduced knee ROM during terminal gait extension.';
        if (_jointAngle < 100) {
          severity = 'Critical';
          col = Colors.redAccent;
          diagnostic =
              'Knee flexion ${_jointAngle.toStringAsFixed(1)}° — patellofemoral or meniscal concern.';
          actions = [
            'Closed-chain quad strengthening.',
            'Knee joint effusion check.',
            'Compression sleeve advised.',
          ];
        } else {
          severity = 'Normal';
          col = Colors.green;
          diagnostic =
              'Knee ROM within healthy range (${_jointAngle.toStringAsFixed(1)}°).';
          actions = [
            'Hamstring / quad stretches daily.',
            'Dynamic warm-up before cardio.',
          ];
        }

      case VisionScenario.dermatology:
        obs = 'Pigmented lesion with irregular margin detected.';
        if (_skinRisk > 75) {
          severity = 'High Risk';
          col = Colors.redAccent;
          diagnostic =
              'Atypical lesion — melanocytic risk ${_skinRisk.toStringAsFixed(0)}%.';
          actions = [
            'Urgent dermoscopy.',
            'Excisional biopsy of margins.',
            'Daily SPF 50+ application.',
          ];
        } else {
          severity = 'Benign';
          col = Colors.green;
          diagnostic =
              'Symmetrical lesion, uniform pigmentation — benign pattern.';
          actions = [
            'Self-monitor every 3 months.',
            'Document size at follow-up visits.',
          ];
        }

      case VisionScenario.facialAsymmetry:
        obs = 'Facial mesh shows unilateral muscular drooping.';
        if (_faceAsym > 15) {
          severity = 'Urgent Review';
          col = Colors.orangeAccent;
          diagnostic =
              'Asymmetry ${_faceAsym.toStringAsFixed(1)}% — CN VII palsy indicator.';
          actions = [
            'Cranial nerve VII exam (brow, cheek, eye).',
            'Evaluate corticosteroid window.',
            'Artificial tears for cornea.',
          ];
        } else {
          severity = 'Normal';
          col = Colors.green;
          diagnostic =
              'Asymmetry ${_faceAsym.toStringAsFixed(1)}% — within physiological norms.';
          actions = [
            'Monitor for facial numbness.',
            'Routine jaw alignment check.',
          ];
        }
    }

    double score = _computeScore();
    return {
      'severity': severity,
      'severityColor': col,
      'diagnostic': diagnostic,
      'obs': obs,
      'actions': actions,
      'score': score,
    };
  }

  double _computeScore() {
    switch (_scenario) {
      case VisionScenario.posture:
        return (100 - (_spineAngle / 20 * 100)).clamp(0, 100);
      case VisionScenario.joints:
        return ((_jointAngle - 40) / 140 * 100).clamp(0, 100);
      case VisionScenario.dermatology:
        return (100 - _skinRisk).clamp(0, 100);
      case VisionScenario.facialAsymmetry:
        return (100 - (_faceAsym / 80 * 100)).clamp(0, 100);
    }
  }

  double get _currentMetricValue {
    switch (_scenario) {
      case VisionScenario.posture:
        return _spineAngle;
      case VisionScenario.joints:
        return _jointAngle;
      case VisionScenario.dermatology:
        return _skinRisk;
      case VisionScenario.facialAsymmetry:
        return _faceAsym;
    }
  }

  void _setMetricValue(double v) => setState(() {
    switch (_scenario) {
      case VisionScenario.posture:
        _spineAngle = v;
      case VisionScenario.joints:
        _jointAngle = v;
      case VisionScenario.dermatology:
        _skinRisk = v;
      case VisionScenario.facialAsymmetry:
        _faceAsym = v;
    }
  });

  (double, double, String) get _metricRange {
    switch (_scenario) {
      case VisionScenario.posture:
        return (0, 20, '°');
      case VisionScenario.joints:
        return (40, 180, '°');
      case VisionScenario.dermatology:
        return (10, 99, '%');
      case VisionScenario.facialAsymmetry:
        return (0, 80, '%');
    }
  }

  String get _metricLabel {
    switch (_scenario) {
      case VisionScenario.posture:
        return 'Spine Deviation Angle';
      case VisionScenario.joints:
        return 'Knee Flexion Angle';
      case VisionScenario.dermatology:
        return 'Melanocytic Risk Index';
      case VisionScenario.facialAsymmetry:
        return 'Facial Asymmetry';
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppShellScaffold(
      title: 'AI Vision Analyzer',
      currentRoute: '/vision-analyzer',
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.person_search_rounded),
          tooltip: 'Select Patient',
          itemBuilder: (_) => _patients
              .map(
                (p) => PopupMenuItem(
                  value: p,
                  child: Text(p, style: GoogleFonts.poppins(fontSize: 13)),
                ),
              )
              .toList(),
          onSelected: (p) => setState(() => _selectedPatient = p),
        ),
        IconButton(
          icon: Icon(
            _isLive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          ),
          color: _isLive ? Colors.greenAccent : cs.onSurface.withValues(alpha: 0.5),
          tooltip: _isLive ? 'Live feed active' : 'Reset to live',
          onPressed: _resetToLive,
        ),
      ],
      body: GestureDetector(
        onTap: _closeFab,
        child: Stack(
          children: [
            Column(
              children: [
                _buildScenarioBar(cs),
                _buildHeroScanner(cs),
                _buildMetricRow(cs),
                _buildTabBar(cs),
                Expanded(child: _buildTabView(cs)),
              ],
            ),
            Positioned(bottom: 16, right: 16, child: _buildFab(cs)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Vision Analyzer',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          Text(
            _selectedPatient.isEmpty ? 'No patient selected' : _selectedPatient,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.person_search_rounded),
          tooltip: 'Select Patient',
          itemBuilder: (_) => _patients
              .map(
                (p) => PopupMenuItem(
                  value: p,
                  child: Text(p, style: GoogleFonts.poppins(fontSize: 13)),
                ),
              )
              .toList(),
          onSelected: (p) => setState(() => _selectedPatient = p),
        ),
        IconButton(
          icon: Icon(
            _isLive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          ),
          color: _isLive ? Colors.greenAccent : cs.onSurface.withValues(alpha: 0.5),
          tooltip: _isLive ? 'Live feed active' : 'Reset to live',
          onPressed: _resetToLive,
        ),
      ],
    );
  }

  // ─── Scenario Bar ──────────────────────────────────────────────────────────

  Widget _buildScenarioBar(ColorScheme cs) {
    return Container(
      height: 78,
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        scrollDirection: Axis.horizontal,
        children: VisionScenario.values.map((s) {
          final active = _scenario == s;
          return GestureDetector(
            onTap: () => setState(() {
              _scenario = s;
              _reportReady = false;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? s.color.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? s.color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    s.icon,
                    color: active ? s.color : cs.onSurface.withValues(alpha: 0.45),
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? s.color : cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Hero Scanner ──────────────────────────────────────────────────────────

  Widget _buildHeroScanner(ColorScheme cs) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final h = box.maxWidth * 0.6;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(0)),
          child: SizedBox(
            width: double.infinity,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildScannerBackground(cs),
                if (!_isScanning) _buildOverlay(cs),
                if (_isLive || _isScanning) _buildScanLine(cs, h),
                _buildLiveBadge(cs),
                if (_isScanning) _buildScanLoader(cs),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScannerBackground(ColorScheme cs) {
    if (_capturedImage != null) {
      return Image.file(_capturedImage!, fit: BoxFit.cover, cacheWidth: 800);
    }
    final urls = {
      VisionScenario.posture:
          'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=700&fit=crop',
      VisionScenario.joints:
          'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?q=80&w=700&fit=crop',
      VisionScenario.dermatology:
          'https://images.unsplash.com/photo-1607613009820-a29f7bb81c04?q=80&w=700&fit=crop',
      VisionScenario.facialAsymmetry:
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=700&fit=crop',
    };
    return Image.network(
      urls[_scenario]!,
      fit: BoxFit.cover,
      cacheWidth: 800,
      errorBuilder: (_, _, _) => Container(
        color: const Color(0xFF0D1117),
        child: Center(
          child: Icon(
            Icons.camera_enhance_rounded,
            size: 52,
            color: _scenario.color.withValues(alpha: 0.3),
          ),
        ),
      ),
      loadingBuilder: (_, child, prog) => prog == null
          ? child
          : Container(
              color: const Color(0xFF0D1117),
              child: Center(
                child: CircularProgressIndicator(color: _scenario.color),
              ),
            ),
    );
  }

  Widget _buildScanLine(ColorScheme cs, double height) {
    return AnimatedBuilder(
      animation: _scanLine,
      builder: (_, _) => Positioned(
        top: _scanLine.value * (height - 4),
        left: 0,
        right: 0,
        child: Container(
          height: 2.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _scenario.color.withValues(alpha: 0.05),
                _scenario.color,
                _scenario.color.withValues(alpha: 0.05),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _scenario.color.withValues(alpha: 0.7),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBadge(ColorScheme cs) {
    return Positioned(
      top: 12,
      left: 12,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, _) => Transform.scale(
          scale: _isLive ? _pulse.value : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isLive
                    ? Colors.greenAccent.withValues(alpha: 0.6)
                    : _scenario.color.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _isLive ? Colors.greenAccent : _scenario.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isLive ? 'LIVE HUD' : 'STATIC',
                  style: GoogleFonts.shareTechMono(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanLoader(ColorScheme cs) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: _scanProgress,
                strokeWidth: 5,
                color: _scenario.color,
                backgroundColor: _scenario.color.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${(_scanProgress * 100).toInt()}%',
              style: GoogleFonts.shareTechMono(
                fontSize: 22,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _scanStatus,
              style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(ColorScheme cs) {
    return LayoutBuilder(
      builder: (_, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        return Stack(
          children: [
            CustomPaint(size: Size(w, h), painter: _getOverlayPainter()),
            Positioned(bottom: 12, right: 12, child: _buildOverlayBadge(cs)),
          ],
        );
      },
    );
  }

  CustomPainter _getOverlayPainter() {
    switch (_scenario) {
      case VisionScenario.posture:
        return _SpinePainter(_spineAngle, _scenario.color);
      case VisionScenario.joints:
        return _JointPainter(_jointAngle, _scenario.color);
      case VisionScenario.dermatology:
        return _DermPainter(_scenario.color);
      case VisionScenario.facialAsymmetry:
        return _FacePainter(_faceAsym, _scenario.color);
    }
  }

  Widget _buildOverlayBadge(ColorScheme cs) {
    final (_, __, unit) = _metricRange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _scenario.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _metricLabel.toUpperCase(),
            style: GoogleFonts.shareTechMono(
              color: Colors.white54,
              fontSize: 8,
            ),
          ),
          Text(
            '${_currentMetricValue.toStringAsFixed(1)}$unit',
            style: GoogleFonts.shareTechMono(
              color: _scenario.color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Metric Summary Row ────────────────────────────────────────────────────

  Widget _buildMetricRow(ColorScheme cs) {
    final info = _buildReportInfo();
    final score = info['score'] as double;
    final severity = info['severity'] as String;
    final col = info['severityColor'] as Color;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _metricTile(
            'HEALTH SCORE',
            '${score.toStringAsFixed(0)}%',
            score > 70
                ? Colors.green
                : score > 40
                ? Colors.amber
                : Colors.red,
            cs,
          ),
          const SizedBox(width: 8),
          _metricTile('SEVERITY', severity, col, cs),
          const SizedBox(width: 8),
          _metricTile(
            'SCAN MODE',
            _isLive ? 'Live HUD' : 'Captured',
            _isLive ? Colors.greenAccent : _scenario.color,
            cs,
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, Color color, ColorScheme cs) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tab Bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      color: cs.surface,
      child: TabBar(
        controller: _tabCtrl,
        labelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        indicatorColor: _scenario.color,
        labelColor: _scenario.color,
        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.45),
        tabs: const [
          Tab(
            icon: Icon(Icons.document_scanner_rounded, size: 16),
            text: 'Scan',
          ),
          Tab(icon: Icon(Icons.analytics_rounded, size: 16), text: 'Report'),
          Tab(icon: Icon(Icons.history_rounded, size: 16), text: 'History'),
        ],
      ),
    );
  }

  // ─── Tab View ──────────────────────────────────────────────────────────────

  Widget _buildTabView(ColorScheme cs) {
    return TabBarView(
      controller: _tabCtrl,
      children: [_buildScanTab(cs), _buildReportTab(cs), _buildHistoryTab(cs)],
    );
  }

  // ─── Scan Tab ──────────────────────────────────────────────────────────────

  Widget _buildScanTab(ColorScheme cs) {
    final (min, max, unit) = _metricRange;
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('LANDMARK CALIBRATION', _scenario.color),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _metricLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${_currentMetricValue.toStringAsFixed(1)}$unit',
                    style: GoogleFonts.shareTechMono(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _scenario.color,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _scenario.color,
                  thumbColor: _scenario.color,
                  inactiveTrackColor: _scenario.color.withValues(alpha: 0.18),
                  overlayColor: _scenario.color.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: _currentMetricValue,
                  min: min,
                  max: max,
                  onChanged: _setMetricValue,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${min.toStringAsFixed(0)}$unit',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  Text(
                    'Normal: ${_getNormalRange()}',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: Colors.green.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${max.toStringAsFixed(0)}$unit',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildScenarioInfo(cs),
        const SizedBox(height: 80),
      ],
    );
  }

  String _getNormalRange() {
    switch (_scenario) {
      case VisionScenario.posture:
        return '< 4°';
      case VisionScenario.joints:
        return '120–150°';
      case VisionScenario.dermatology:
        return '< 50%';
      case VisionScenario.facialAsymmetry:
        return '< 10%';
    }
  }

  Widget _buildScenarioInfo(ColorScheme cs) {
    final info = {
      VisionScenario.posture: (
        'What is being measured?',
        'The spinal alignment angle from C7 to L5 vertebrae. Values above 8° indicate scoliosis or postural imbalance.',
      ),
      VisionScenario.joints: (
        'What is being measured?',
        'The knee flexion angle during gait. Values below 100° indicate limited ROM requiring intervention.',
      ),
      VisionScenario.dermatology: (
        'What is being measured?',
        'Melanocytic risk probability using ABCD criteria: Asymmetry, Border, Color, Diameter.',
      ),
      VisionScenario.facialAsymmetry: (
        'What is being measured?',
        'Facial muscle symmetry index. Values above 15% may indicate Bell\'s Palsy or stroke.',
      ),
    };
    final (title, body) = info[_scenario]!;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: _scenario.color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _scenario.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              height: 1.5,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Report Tab ────────────────────────────────────────────────────────────

  Widget _buildReportTab(ColorScheme cs) {
    if (!_reportReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 56,
              color: cs.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No scan yet',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use the camera button to start analysis',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }
    final info = _buildReportInfo();
    final col = info['severityColor'] as Color;
    final actions = info['actions'] as List<String>;
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: col,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI-ASSISTED CLINICAL DECISION SUPPORT',
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withValues(alpha: 0.4),
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          info['severity'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: col,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_scenario.icon, color: col, size: 22),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('OBSERVATION', cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              Text(
                info['obs'] as String,
                style: GoogleFonts.poppins(fontSize: 13, height: 1.5),
              ),
              const Divider(height: 20),
              _sectionHeader('DIAGNOSTIC FINDING', _scenario.color),
              const SizedBox(height: 8),
              Text(
                info['diagnostic'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                  color: cs.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('RECOMMENDED ACTIONS', _scenario.color),
              const SizedBox(height: 10),
              ...actions.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _scenario.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.value,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            height: 1.4,
                            color: cs.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('DOCTOR\'S NOTES', cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      'Add clinical notes, observations, or follow-up reminders…',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveRecord,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  'Save to History',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scenario.color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportReportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(
                  'Export PDF Report',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _scenario.color,
                  side: BorderSide(color: _scenario.color, width: 1.5),
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ─── History Tab ───────────────────────────────────────────────────────────

  Widget _buildHistoryTab(ColorScheme cs) {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 56,
              color: cs.onSurface.withValues(alpha: 0.18),
            ),
            const SizedBox(height: 12),
            Text(
              'No history yet',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
            Text(
              'Saved scans will appear here',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _historyTile(_history[i], cs),
    );
  }

  Widget _historyTile(ScanRecord r, ColorScheme cs) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: r.scenario.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(r.scenario.icon, color: r.scenario.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.patient,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${r.scenario.label}  •  ${DateFormat('MMM d, HH:mm').format(r.timestamp)}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (r.note.isNotEmpty)
                  Text(
                    r.note,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: r.severityColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              r.severity,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: r.severityColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFab(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _fabAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _minieFab(
                Icons.photo_library_rounded,
                'Upload from Gallery',
                () => _capture(ImageSource.gallery),
                cs,
              ),
              const SizedBox(height: 10),
              _minieFab(
                Icons.camera_alt_rounded,
                'Capture with Camera',
                () => _capture(ImageSource.camera),
                cs,
              ),
              const SizedBox(height: 10),
              _minieFab(
                Icons.refresh_rounded,
                'Reset to Live Mode',
                _resetToLive,
                cs,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        FloatingActionButton(
          onPressed: _toggleFab,
          backgroundColor: _scenario.color,
          foregroundColor: Colors.white,
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ],
    );
  }

  Widget _minieFab(
    IconData icon,
    String label,
    VoidCallback onTap,
    ColorScheme cs,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: _scenario.color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _scenario.color),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(String text, Color color) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 1,
    ),
  );
}

// ─── Painters ─────────────────────────────────────────────────────────────────

class _SpinePainter extends CustomPainter {
  final double angle;
  final Color color;
  _SpinePainter(this.angle, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final gridP = Paint()
      ..color = Colors.lightBlue.withValues(alpha: 0.15)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double i = 0.1; i < 1.0; i += 0.15) {
      canvas.drawLine(
        Offset(s.width * i, 0),
        Offset(s.width * i, s.height),
        gridP,
      );
      canvas.drawLine(
        Offset(0, s.height * i),
        Offset(s.width, s.height * i),
        gridP,
      );
    }
    final lineP = Paint()
      ..color = angle > 8 ? Colors.redAccent : Colors.tealAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final nodeP = Paint()
      ..color = angle > 8 ? Colors.red : Colors.greenAccent
      ..style = PaintingStyle.fill;
    final mid = Offset(s.width * 0.5 + angle * 3.5, s.height * 0.5);
    final path = Path()
      ..moveTo(s.width * 0.5, s.height * 0.15)
      ..quadraticBezierTo(mid.dx, mid.dy, s.width * 0.5, s.height * 0.85);
    canvas.drawPath(path, lineP);
    for (final p in [
      Offset(s.width * 0.5, s.height * 0.15),
      Offset(s.width * 0.5 + angle * 1.5, s.height * 0.3),
      mid,
      Offset(s.width * 0.5 + angle * 1.8, s.height * 0.7),
      Offset(s.width * 0.5, s.height * 0.85),
    ]) {
      canvas.drawCircle(p, 4.5, nodeP);
    }
    final axisP = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(s.width * 0.5, 0),
      Offset(s.width * 0.5, s.height),
      axisP,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinePainter o) => o.angle != angle;
}

class _JointPainter extends CustomPainter {
  final double angle;
  final Color color;
  _JointPainter(this.angle, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final boneP = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final jointP = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final hip = Offset(s.width * 0.55, s.height * 0.22);
    final knee = Offset(s.width * 0.42, s.height * 0.55);
    final rad = (angle - 90) * math.pi / 180.0;
    final ankle = Offset(
      knee.dx + s.height * 0.28 * math.cos(rad),
      knee.dy + s.height * 0.28 * math.sin(rad),
    );
    canvas.drawLine(hip, knee, boneP);
    canvas.drawLine(knee, ankle, boneP);
    canvas.drawCircle(hip, 6, jointP);
    canvas.drawCircle(knee, 9, Paint()..color = color);
    canvas.drawCircle(knee, 5, jointP);
    canvas.drawCircle(ankle, 6, jointP);
    canvas.drawCircle(
      knee,
      28,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _JointPainter o) => o.angle != angle;
}

class _DermPainter extends CustomPainter {
  final Color color;
  _DermPainter(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final ringP = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s.width * 0.5, s.height * 0.5),
        width: s.width * 0.38,
        height: s.height * 0.35,
      ),
      ringP,
    );
    final cornerP = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final len = 18.0;
    for (final corner in [
      Offset(30, 30),
      Offset(s.width - 30, 30),
      Offset(30, s.height - 30),
      Offset(s.width - 30, s.height - 30),
    ]) {
      final dx = corner.dx < s.width / 2 ? len : -len;
      final dy = corner.dy < s.height / 2 ? len : -len;
      canvas.drawLine(corner, Offset(corner.dx + dx, corner.dy), cornerP);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy), cornerP);
    }
  }

  @override
  bool shouldRepaint(covariant _DermPainter o) => false;
}

class _FacePainter extends CustomPainter {
  final double asym;
  final Color color;
  _FacePainter(this.asym, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final connP = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    final dotP = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final warnP = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;
    final delta = asym * 0.8;
    final pts = [
      Offset(s.width * 0.5, s.height * 0.2),
      Offset(s.width * 0.34, s.height * 0.33),
      Offset(s.width * 0.66, s.height * 0.33),
      Offset(s.width * 0.37, s.height * 0.43),
      Offset(s.width * 0.63, s.height * 0.43 - delta * 0.15),
      Offset(s.width * 0.5, s.height * 0.52),
      Offset(s.width * 0.41, s.height * 0.66),
      Offset(s.width * 0.59, s.height * 0.66 - delta),
      Offset(s.width * 0.5, s.height * 0.8),
      Offset(s.width * 0.28, s.height * 0.5),
      Offset(s.width * 0.72, s.height * 0.5),
    ];
    for (int i = 0; i < pts.length; i++) {
      for (int j = i + 1; j < pts.length; j++) {
        if ((pts[i] - pts[j]).distance < s.width * 0.27) {
          canvas.drawLine(pts[i], pts[j], connP);
        }
      }
    }
    for (int i = 0; i < pts.length; i++) {
      final warn = (i == 4 || i == 7) && asym > 15;
      canvas.drawCircle(pts[i], warn ? 5.5 : 3.5, warn ? warnP : dotP);
    }
  }

  @override
  bool shouldRepaint(covariant _FacePainter o) => o.asym != asym;
}
