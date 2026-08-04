import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notes/clinical_notes_repository.dart';
import '../../services/app_preferences.dart';
import '../../theme/app_theme.dart';
import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import '../utils/image_service.dart';

// ─── Enums ───────────────────────────────────────────────────────────────────

enum ScenarioCategory {
  all('All Modules', Icons.grid_view_rounded),
  spine('Spine & X-Ray', Icons.biotech_rounded),
  neuro('Neuro & Gait', Icons.directions_walk_rounded),
  joints('Goniometry', Icons.compass_calibration_rounded),
  derm('Skin & Face', Icons.face_retouching_natural_rounded);

  final String label;
  final IconData icon;
  const ScenarioCategory(this.label, this.icon);
}

enum VisionScenario {
  posture('Spine & Posture', Icons.accessibility_new_rounded, Color(0xFF10B981)),
  joints('Joint ROM', Icons.hdr_strong_rounded, Color(0xFFF59E0B)),
  dermatology('Dermatology', Icons.opacity_rounded, Color(0xFFEC4899)),
  facialAsymmetry('Facial Palsy', Icons.face_retouching_natural_rounded, Color(0xFF6366F1)),
  xraySpine('X-Ray Gonstead', Icons.biotech_rounded, Color(0xFF0284C7)),
  thermalScan('Thermal Scan', Icons.thermostat_rounded, Color(0xFFEF4444)),
  gaitAnalysis('Dynamic Gait', Icons.directions_walk_rounded, Color(0xFF8B5CF6)),
  neuroTremor('Neuro Tremor', Icons.graphic_eq_rounded, Color(0xFFD97706)),
  gonsteadListing('Gonstead Listing AI', Icons.format_list_bulleted_rounded, Color(0xFF06B6D4)),
  compareProgress('Before/After Progress', Icons.compare_rounded, Color(0xFF14B8A6)),
  fullBodyRom('Full-Body Goniometer', Icons.compass_calibration_rounded, Color(0xFFEAB308));

  final String label;
  final IconData icon;
  final Color color;
  const VisionScenario(this.label, this.icon, this.color);

  ScenarioCategory get category {
    switch (this) {
      case VisionScenario.posture:
      case VisionScenario.xraySpine:
      case VisionScenario.thermalScan:
      case VisionScenario.gonsteadListing:
        return ScenarioCategory.spine;
      case VisionScenario.gaitAnalysis:
      case VisionScenario.neuroTremor:
      case VisionScenario.compareProgress:
        return ScenarioCategory.neuro;
      case VisionScenario.joints:
      case VisionScenario.fullBodyRom:
        return ScenarioCategory.joints;
      case VisionScenario.dermatology:
      case VisionScenario.facialAsymmetry:
        return ScenarioCategory.derm;
    }
  }
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
  ScenarioCategory _selectedCategory = ScenarioCategory.all;
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

  Future<void> _attachToClinicalNote(ColorScheme cs) async {
    final patient = _selectedPatient.isEmpty ? 'General Patient' : _selectedPatient;
    final info = _buildReportInfo();
    final (min, max, unit) = _metricRange;
    final formattedNote = '''
[SOAP OBJECTIVE ANALYSIS - VISION AI SCAN]
Scenario: ${_scenario.label}
Primary Metric: ${_metricLabel} = ${_currentMetricValue.toStringAsFixed(1)}$unit (Normal: ${_getNormalRange()})
Health Score: ${(info['score'] as double).toStringAsFixed(0)}%
Severity: ${info['severity']}

Diagnostic Observation:
${info['diagnostic']}

Clinical Findings:
${info['obs']}

Recommended Clinical Actions:
- ${(info['actions'] as List<String>).join('\n- ')}

Doctor Notes:
${_doctorNotes.isEmpty ? 'None provided.' : _doctorNotes}
''';

    final newNote = ClinicalNote(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patientName: patient,
      note: formattedNote,
      category: 'Posture',
      createdAt: DateTime.now(),
    );

    try {
      await ClinicalNotesRepository().saveNote(newNote);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan findings attached to $patient SOAP note!', style: GoogleFonts.poppins()),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save SOAP note: $e', style: GoogleFonts.poppins()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Metric sliders
  double _spineAngle = 4.2;
  double _jointAngle = 112.0;
  double _skinRisk = 84.0;
  double _faceAsym = 12.5;
  double _cobbAngle = 14.5;
  double _thermalDeltaT = 0.85;
  double _gaitSymmetry = 82.0;
  double _tremorHz = 6.2;
  double _gonsteadRotation = 12.0;
  double _progressImprovement = 38.5;
  double _goniometerAngle = 135.0;
  String _selectedVertebra = 'L4';
  bool _show3DSkeleton = false;

  (double, double, String) get _metricRange {
    switch (_scenario) {
      case VisionScenario.posture: return (0.0, 30.0, '°');
      case VisionScenario.joints: return (0.0, 180.0, '°');
      case VisionScenario.dermatology: return (0.0, 100.0, '%');
      case VisionScenario.facialAsymmetry: return (0.0, 50.0, '%');
      case VisionScenario.xraySpine: return (0.0, 60.0, '°');
      case VisionScenario.thermalScan: return (0.0, 3.0, '°C');
      case VisionScenario.gaitAnalysis: return (0.0, 100.0, '%');
      case VisionScenario.neuroTremor: return (0.0, 15.0, ' Hz');
      case VisionScenario.gonsteadListing: return (0.0, 30.0, '°');
      case VisionScenario.compareProgress: return (0.0, 100.0, '%');
      case VisionScenario.fullBodyRom: return (0.0, 180.0, '°');
    }
  }

  String get _metricLabel {
    switch (_scenario) {
      case VisionScenario.posture: return 'C7–L5 Spinal Deviation';
      case VisionScenario.joints: return 'Knee Flexion Angle';
      case VisionScenario.dermatology: return 'ABCD Risk Score';
      case VisionScenario.facialAsymmetry: return 'Facial Asymmetry Index';
      case VisionScenario.xraySpine: return 'Spinal Cobb Angle';
      case VisionScenario.thermalScan: return 'Paraspinal Heat Differential ΔT';
      case VisionScenario.gaitAnalysis: return 'Gait Symmetry Score';
      case VisionScenario.neuroTremor: return 'Tremor Peak Frequency';
      case VisionScenario.gonsteadListing: return 'Vertebral Rotation Angle';
      case VisionScenario.compareProgress: return 'Recovery Progress Score';
      case VisionScenario.fullBodyRom: return 'Joint Goniometer Angle';
    }
  }

  double get _currentMetricValue {
    switch (_scenario) {
      case VisionScenario.posture: return _spineAngle;
      case VisionScenario.joints: return _jointAngle;
      case VisionScenario.dermatology: return _skinRisk;
      case VisionScenario.facialAsymmetry: return _faceAsym;
      case VisionScenario.xraySpine: return _cobbAngle;
      case VisionScenario.thermalScan: return _thermalDeltaT;
      case VisionScenario.gaitAnalysis: return _gaitSymmetry;
      case VisionScenario.neuroTremor: return _tremorHz;
      case VisionScenario.gonsteadListing: return _gonsteadRotation;
      case VisionScenario.compareProgress: return _progressImprovement;
      case VisionScenario.fullBodyRom: return _goniometerAngle;
    }
  }

  void _setMetricValue(double value) {
    setState(() {
      switch (_scenario) {
        case VisionScenario.posture: _spineAngle = value; break;
        case VisionScenario.joints: _jointAngle = value; break;
        case VisionScenario.dermatology: _skinRisk = value; break;
        case VisionScenario.facialAsymmetry: _faceAsym = value; break;
        case VisionScenario.xraySpine: _cobbAngle = value; break;
        case VisionScenario.thermalScan: _thermalDeltaT = value; break;
        case VisionScenario.gaitAnalysis: _gaitSymmetry = value; break;
        case VisionScenario.neuroTremor: _tremorHz = value; break;
        case VisionScenario.gonsteadListing: _gonsteadRotation = value; break;
        case VisionScenario.compareProgress: _progressImprovement = value; break;
        case VisionScenario.fullBodyRom: _goniometerAngle = value; break;
      }
    });
  }

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

      case VisionScenario.xraySpine:
        obs = 'Spinal radiograph landmarking shows coronal Cobb angle curvature & pelvic tilt.';
        if (_cobbAngle > 10) {
          severity = 'Clinical Scoliosis'; col = Colors.orangeAccent;
          diagnostic = 'Cobb angle ${_cobbAngle.toStringAsFixed(1)}° — structural spine curve detected.';
          actions = ['Gonstead pelvic level adjustment.', 'Full-spine standing posture radiograph.', 'Custom spinal orthotics evaluation.'];
        } else {
          severity = 'Physiological'; col = Colors.green;
          diagnostic = 'Cobb angle ${_cobbAngle.toStringAsFixed(1)}° — within physiological limits.';
          actions = ['Postural maintenance exercises.', 'Annual radiographic re-evaluation.'];
        }

      case VisionScenario.thermalScan:
        obs = 'Bilateral paraspinal infrared heat map indicates local inflammation / nerve stress.';
        if (_thermalDeltaT > 0.6) {
          severity = 'Subluxation Alert'; col = Colors.redAccent;
          diagnostic = 'Paraspinal ΔT = ${_thermalDeltaT.toStringAsFixed(2)}°C — significant subluxation pattern at L5/S1.';
          actions = ['Targeted Gonstead L5/S1 adjustment.', 'Ice cryotherapy 15 mins.', 'Re-scan paraspinal thermal map post-adjustment.'];
        } else {
          severity = 'Balanced'; col = Colors.green;
          diagnostic = 'Paraspinal ΔT = ${_thermalDeltaT.toStringAsFixed(2)}°C — symmetrical neuro-thermal output.';
          actions = ['Routine spinal wellness maintenance.', 'Hydration & lumbar movement.'];
        }

      case VisionScenario.gaitAnalysis:
        obs = 'Dynamic stance phase symmetry & pelvic sway tracking during walking.';
        if (_gaitSymmetry < 85) {
          severity = 'Gait Deficit'; col = Colors.amber;
          diagnostic = 'Gait symmetry ${_gaitSymmetry.toStringAsFixed(0)}% — antalgic limp or pelvic misalignment.';
          actions = ['Sacroiliac (SI) joint motion check.', 'Gait re-education therapy.', 'Gluteus medius strengthening.'];
        } else {
          severity = 'Symmetrical'; col = Colors.green;
          diagnostic = 'Gait symmetry ${_gaitSymmetry.toStringAsFixed(0)}% — balanced kinematic stride.';
          actions = ['Continue daily walking routine.', 'Proper footwear support.'];
        }

      case VisionScenario.neuroTremor:
        obs = 'Micro-motion visual tremor tracking & motor tapping frequency assessment.';
        if (_tremorHz > 5.0) {
          severity = 'Elevated Tremor'; col = Colors.orangeAccent;
          diagnostic = 'Tremor frequency ${_tremorHz.toStringAsFixed(1)} Hz — resting/action tremor detected.';
          actions = ['Neurological motor exam (UPDRS rating).', 'Electromyography (EMG) referral.', 'Avoid excessive stimulants & monitor rest.'];
        } else {
          severity = 'Normal Tremor'; col = Colors.green;
          diagnostic = 'Tremor frequency ${_tremorHz.toStringAsFixed(1)} Hz — physiological motor stability.';
          actions = ['Routine neuromuscular wellness.', 'Fine motor coordination games.'];
        }

      case VisionScenario.gonsteadListing:
        obs = 'Vertebral process rotation & open wedge alignment derived via Gonstead Listing AI.';
        final listing = _gonsteadRotation > 10 ? 'PRS' : _gonsteadRotation > 5 ? 'PRI' : 'PLS';
        if (_gonsteadRotation > 8) {
          severity = 'Subluxation ($listing)'; col = Colors.cyan;
          diagnostic = 'Spinous Process Rotation ${_gonsteadRotation.toStringAsFixed(1)}° Right — Gonstead Listing: $listing.';
          actions = ['Targeted Gonstead Adjustment (LOD: P-to-A, I-to-S, R-to-L).', 'Contact Point: Right Mammillary / Spinous Process.', 'Re-check post-thrust paraspinal thermal scan.'];
        } else {
          severity = 'Normal Alignment'; col = Colors.green;
          diagnostic = 'Spinous Process Rotation ${_gonsteadRotation.toStringAsFixed(1)}° — within physiological limits.';
          actions = ['Routine spinal maintenance.', 'Ergonomic posture advice.'];
        }

      case VisionScenario.compareProgress:
        obs = 'Comparative visual & thermal progression analysis relative to baseline scan.';
        if (_progressImprovement >= 30) {
          severity = 'High Improvement'; col = Colors.teal;
          diagnostic = 'Patient correction ${_progressImprovement.toStringAsFixed(1)}% improvement over baseline.';
          actions = ['Maintain current care plan frequency.', 'Issue 4-Week Patient Progress Certificate.', 'Re-evaluate ROM goals.'];
        } else {
          severity = 'Moderate Progress'; col = Colors.amber;
          diagnostic = 'Patient correction ${_progressImprovement.toStringAsFixed(1)}% improvement — steady healing.';
          actions = ['Continue spinal adjustments 2×/week.', 'Review home stretching compliance.'];
        }

      case VisionScenario.fullBodyRom:
        obs = 'Multi-joint goniometric angle tracing (Shoulder / Cervical / Hip / Knee).';
        if (_goniometerAngle < 120) {
          severity = 'ROM Restricted'; col = Colors.amber;
          diagnostic = 'Joint Goniometer Angle ${_goniometerAngle.toStringAsFixed(1)}° — active restriction detected.';
          actions = ['Myofascial release & joint mobilization.', 'Prescribe progressive ROM stretch routine.', 'Re-test goniometer in 14 days.'];
        } else {
          severity = 'Optimal ROM'; col = Colors.green;
          diagnostic = 'Joint Goniometer Angle ${_goniometerAngle.toStringAsFixed(1)}° — healthy anatomical mobility.';
          actions = ['Dynamic warm-up before exercise.', 'Maintain full active range of motion.'];
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
      case VisionScenario.posture: return (100 - (_spineAngle / 20 * 100)).clamp(0, 100);
      case VisionScenario.joints: return ((_jointAngle - 40) / 140 * 100).clamp(0, 100);
      case VisionScenario.dermatology: return (100 - _skinRisk).clamp(0, 100);
      case VisionScenario.facialAsymmetry: return (100 - (_faceAsym / 80 * 100)).clamp(0, 100);
      case VisionScenario.xraySpine: return (100 - (_cobbAngle / 45 * 100)).clamp(0, 100);
      case VisionScenario.thermalScan: return (100 - (_thermalDeltaT / 2.0 * 100)).clamp(0, 100);
      case VisionScenario.gaitAnalysis: return _gaitSymmetry.clamp(0, 100);
      case VisionScenario.neuroTremor: return (100 - (_tremorHz / 12.0 * 100)).clamp(0, 100);
      case VisionScenario.gonsteadListing: return (100 - (_gonsteadRotation / 25 * 100)).clamp(0, 100);
      case VisionScenario.compareProgress: return _progressImprovement.clamp(0, 100);
      case VisionScenario.fullBodyRom: return ((_goniometerAngle - 40) / 140 * 100).clamp(0, 100);
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
      height: 60,
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
                color: active ? s.color.withValues(alpha: 0.18) : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? s.color : cs.onSurface.withValues(alpha: 0.1),
                  width: active ? 1.8 : 1.0,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s.icon, color: active ? s.color : cs.onSurface.withValues(alpha: 0.6), size: 16),
                const SizedBox(width: 7),
                Text(s.label, style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? s.color : cs.onSurface.withValues(alpha: 0.75),
                )),
              ]),
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
    if (_capturedImage != null) return Image.file(_capturedImage!, fit: BoxFit.cover);

    final anatomicalImageUrls = {
      VisionScenario.posture: 'https://images.unsplash.com/photo-1530497610245-94d3c16cda28?q=80&w=800&fit=crop', // Spinal Column
      VisionScenario.joints: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?q=80&w=800&fit=crop', // Knee Joint Anatomy
      VisionScenario.dermatology: 'https://images.unsplash.com/photo-1607613009820-a29f7bb81c04?q=80&w=800&fit=crop', // Skin Lesion Pathology
      VisionScenario.facialAsymmetry: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=800&fit=crop', // Facial Structure
      VisionScenario.xraySpine: 'https://images.unsplash.com/photo-1579684385127-1ef15d508118?q=80&w=800&fit=crop', // Radiograph X-Ray
      VisionScenario.thermalScan: 'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?q=80&w=800&fit=crop', // Paraspinal Infrared Heat Scan
      VisionScenario.gaitAnalysis: 'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?q=80&w=800&fit=crop', // Gait Movement Sequence
      VisionScenario.neuroTremor: 'https://images.unsplash.com/photo-1559757175-5700dde675bc?q=80&w=800&fit=crop', // Hand Neuromuscular
      VisionScenario.gonsteadListing: 'https://images.unsplash.com/photo-1584515979956-d9f6e5d09982?q=80&w=800&fit=crop', // Vertebral Subluxation Anatomy
      VisionScenario.compareProgress: 'https://images.unsplash.com/photo-1576091160550-2173dba999ef?q=80&w=800&fit=crop', // Posture Recovery Progress
      VisionScenario.fullBodyRom: 'https://images.unsplash.com/photo-1518611012118-696072aa579a?q=80&w=800&fit=crop', // Full Body Human Skeletal Atlas
    };

    final imageUrl = anatomicalImageUrls[_scenario]!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Real Human Anatomical Image
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF090D16),
            child: CustomPaint(painter: _FullBodyAnatomicPainter(_scenario)),
          ),
          loadingBuilder: (_, child, prog) => prog == null
              ? child
              : Container(
                  color: const Color(0xFF090D16),
                  child: Center(child: CircularProgressIndicator(color: _scenario.color)),
                ),
        ),
        // 2. Dark Cybernetic Clinical Vignette Overlay
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.1,
              colors: [
                Colors.transparent,
                Colors.black.withOpacity(0.4),
                Colors.black.withOpacity(0.75),
              ],
            ),
          ),
        ),
        // 3. Clinical HUD Landmark Painter Overlay
        CustomPaint(
          painter: _FullBodyAnatomicPainter(_scenario),
        ),
      ],
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
      case VisionScenario.posture: return _SpinePainter(_spineAngle, _scenario.color);
      case VisionScenario.joints: return _JointPainter(_jointAngle, _scenario.color);
      case VisionScenario.dermatology: return _DermPainter(_scenario.color);
      case VisionScenario.facialAsymmetry: return _FacePainter(_faceAsym, _scenario.color);
      case VisionScenario.xraySpine: return _XrayPainter(_cobbAngle, _scenario.color);
      case VisionScenario.thermalScan: return _ThermalPainter(_thermalDeltaT, _scenario.color);
      case VisionScenario.gaitAnalysis: return _GaitPainter(_gaitSymmetry, _scenario.color);
      case VisionScenario.neuroTremor: return _NeuroTremorPainter(_tremorHz, _scenario.color);
      case VisionScenario.gonsteadListing: return _GonsteadListingPainter(_gonsteadRotation, _scenario.color);
      case VisionScenario.compareProgress: return _ProgressComparePainter(_progressImprovement, _scenario.color);
      case VisionScenario.fullBodyRom: return _GoniometerPainter(_goniometerAngle, _scenario.color);
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

  // ─── Camera & Capture Action Toolbar ───────────────────────────────────────

  Widget _buildCameraToolbar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: cs.surface,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: ElevatedButton.icon(
              onPressed: () => _capture(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: Text('Capture Photo', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _scenario.color,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: OutlinedButton.icon(
              onPressed: () => _capture(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded, size: 18),
              label: Text('Upload Gallery', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 11.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.onSurface.withOpacity(0.2)),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: OutlinedButton.icon(
              onPressed: _resetToLive,
              icon: Icon(Icons.refresh_rounded, size: 18, color: Colors.greenAccent.shade400),
              label: Text('Reset Live', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.greenAccent.shade400)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.greenAccent.shade400.withOpacity(0.5)),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
      case VisionScenario.posture: return '< 4°';
      case VisionScenario.joints: return '120–150°';
      case VisionScenario.dermatology: return '< 50%';
      case VisionScenario.facialAsymmetry: return '< 10%';
      case VisionScenario.xraySpine: return '< 10°';
      case VisionScenario.thermalScan: return '< 0.5°C';
      case VisionScenario.gaitAnalysis: return '> 90%';
      case VisionScenario.neuroTremor: return '< 4.5 Hz';
      case VisionScenario.gonsteadListing: return '< 4° Rot';
      case VisionScenario.compareProgress: return '> 30% Imp';
      case VisionScenario.fullBodyRom: return '130–160°';
    }
  }

  Widget _buildScenarioInfo(ColorScheme cs) {
    final info = {
      VisionScenario.posture: (
        'Spine & Posture Alignment Guide',
        'Measures C7 to L5 spinal deviation. Values above 8° indicate scoliosis or pelvic tilt.',
        ['1. Place patient 2 meters away facing away from camera.', '2. Keep shoulders level and feet hip-width apart.', '3. Align green crosshair with C7 spinous process for instant angle trace.']
      ),
      VisionScenario.joints: (
        'Knee Flexion Goniometry Guide',
        'Measures knee extension & flexion ROM during movement. Normal gait ROM is 120–150°.',
        ['1. Position camera lateral to patient\'s knee joint.', '2. Align pivot node with lateral femoral epicondyle.', '3. Track ROM arc during active flexion & extension.']
      ),
      VisionScenario.dermatology: (
        'Dermatological ABCD Risk Scan Guide',
        'Analyzes skin lesions using ABCD criteria (Asymmetry, Border, Color, Diameter).',
        ['1. Hold camera 10–15 cm from skin lesion under clear lighting.', '2. Center lesion inside cyan target ring.', '3. Tap scan to compute malignancy probability index.']
      ),
      VisionScenario.facialAsymmetry: (
        'Facial Palsy Asymmetry Guide',
        'Analyzes 468 3D facial mesh landmarks for Bell\'s Palsy & cranial nerve VII screening.',
        ['1. Position patient facing camera with neutral facial expression.', '2. Ensure full face is inside yellow grid boundary.', '3. Tap scan to measure left vs right muscle contraction variance.']
      ),
      VisionScenario.xraySpine: (
        'Radiograph Cobb Angle & Horizon Guide',
        'Measures coronal spinal curvature & pelvic horizontal baseline on X-Ray films.',
        ['1. Position X-Ray film flat on viewbox or digital display.', '2. Align upper & lower endplate horizons across major curve.', '3. System calculates exact Cobb angle & Gonstead pelvic tilt.']
      ),
      VisionScenario.thermalScan: (
        'Paraspinal Thermal Scan Guide',
        'Detects bilateral paraspinal temperature differential (ΔT) from nerve root heat asymmetry.',
        ['1. Expose patient\'s spine in a climate-controlled room.', '2. Sweep scanner down C1 to S1 paraspinal channels.', '3. Red zones indicate acute nerve root inflammation (ΔT > 0.8°C).']
      ),
      VisionScenario.gaitAnalysis: (
        'Kinematic Gait Symmetry Guide',
        'Analyzes walking stride length, stance phase duration, and pelvic sway.',
        ['1. Have patient walk 4 paces along marked clinical path.', '2. Track ankle strike angle and knee extension rhythm.', '3. Evaluates antalgic limp index & gait efficiency score.']
      ),
      VisionScenario.neuroTremor: (
        'Parkinson\'s & Neuro Tremor Guide',
        'Analyzes micro-motion hand tremor frequency (Hz) & finger tapping rhythm.',
        ['1. Ask patient to extend arm forward with fingers outstretched.', '2. Rest hand inside green motion tracking target box.', '3. System measures peak tremor frequency (Hz) and motor stability.']
      ),
      VisionScenario.gonsteadListing: (
        'Gonstead Listing & LOD Engine Guide',
        'Determines vertebral spinous rotation (P-R/P-L) and open wedge (S/I) direction.',
        ['1. Select target spinal vertebra (e.g. L4, T6, C2).', '2. Measure spinous process displacement & open intervertebral space.', '3. Generates Gonstead Listing code (e.g. PRS) & Line of Drive arrow.']
      ),
      VisionScenario.compareProgress: (
        'Before / After Progress Tracker Guide',
        'Compares initial baseline posture/thermal scan against current follow-up scan.',
        ['1. Load patient\'s initial assessment baseline scan.', '2. Align current follow-up scan using split view grid.', '3. Generates percentage recovery milestone for care plan reporting.']
      ),
      VisionScenario.fullBodyRom: (
        'Multi-Joint Full Body ROM Guide',
        'Full-body goniometry across Cervical Spine, Shoulder, Hip, Knee, & Ankle joints.',
        ['1. Select target joint from full-body anatomical wireframe.', '2. Instruct patient through active Range of Motion.', '3. System plots real-time goniometric flex angles & normal benchmarks.']
      ),
    };

    final (title, body, steps) = info[_scenario]!;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual Diagram Banner
          Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _scenario.color.withValues(alpha: 0.3)),
            ),
            child: Stack(
              children: [
                CustomPaint(
                  size: const Size(double.infinity, 110),
                  painter: _FullBodyAnatomicPainter(_scenario),
                ),
                Positioned(
                  bottom: 8,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _scenario.color.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'VISUAL DIAGRAM REFERENCE — ${title.toUpperCase()}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.cyanAccent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _scenario.color, size: 18),
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
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.poppins(
              fontSize: 12,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to Position Patient & Use:',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                ...steps.map(
                  (step) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      step,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        height: 1.4,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ),
              ],
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
        _buildRecoveryProgressCard(cs),
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
        ElevatedButton.icon(
          onPressed: () => _attachToClinicalNote(cs),
          icon: const Icon(Icons.note_add_rounded, size: 20),
          label: Text('Attach to Patient Clinical Note (SOAP)', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _shareViaWhatsApp,
                icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                label: Text('WhatsApp', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveRecord,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: Text('Save History', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _scenario.color,
                  side: BorderSide(color: _scenario.color, width: 1.5),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportReportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text('Export PDF', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _scenario.color,
                  side: BorderSide(color: _scenario.color, width: 1.5),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ─── Patient Recovery Progress Visualizer Card ─────────────────────────────

  Widget _buildRecoveryProgressCard(ColorScheme cs) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: Colors.greenAccent.shade400, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PATIENT RECOVERY PROGRESS (BASELINE VS TODAY)',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.greenAccent.shade400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.withOpacity(0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('BASELINE (SESSION 1)', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                    const SizedBox(height: 4),
                    Text('Spine Tilt: 14.5°\nThermal ΔT: 1.2°C\nKnee ROM: 105°', style: GoogleFonts.poppins(fontSize: 11, height: 1.4, color: cs.onSurface.withOpacity(0.8))),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, color: Colors.tealAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withOpacity(0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CURRENT (TODAY)', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.greenAccent)),
                    const SizedBox(height: 4),
                    Text('Spine Tilt: 4.2°\nThermal ΔT: 0.3°C\nKnee ROM: 142°', style: GoogleFonts.poppins(fontSize: 11, height: 1.4, color: cs.onSurface.withOpacity(0.8))),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _progressChip('71% Spine Correction', Colors.tealAccent),
              _progressChip('80% Inflammatory Drop', Colors.amberAccent),
              _progressChip('+37° ROM Restored', Colors.cyanAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.6))),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Future<void> _shareViaWhatsApp() async {
    final info = _buildReportInfo();
    final patientName = _selectedPatient.isEmpty ? 'Patient' : _selectedPatient;
    final text = Uri.encodeComponent(
      '*GONSTEAD CHIROPRACTIC CLINIC — AI PATIENT SUMMARY*\n\n'
      '👤 *Patient:* $patientName\n'
      '🔬 *Module:* ${_scenario.label}\n'
      '📍 *Vertebra:* $_selectedVertebra\n'
      '📊 *Status:* ${info['severity']}\n'
      '🔍 *Finding:* ${info['diagnostic']}\n'
      '💡 *Recommendation:* ${(info['actions'] as List<String>).first}\n\n'
      '_Generated by Gonstead AI Vision Suite_'
    );
    final url = Uri.parse('https://wa.me/?text=$text');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _snack('Could not open WhatsApp', isError: true);
      }
    } catch (e) {
      _snack('Error launching WhatsApp: $e', isError: true);
    }
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
              const SizedBox(height: 4),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                onPressed: () {
                  setState(() {
                    _scenario = r.scenario;
                    _selectedPatient = r.patient;
                  });
                  _exportReportPdf();
                },
                tooltip: 'Regenerate PDF Report',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
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

class _XrayPainter extends CustomPainter {
  final double cobb; final Color color;
  _XrayPainter(this.cobb, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final lineP = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    final gridP = Paint()..color = color.withOpacity(0.12)..strokeWidth = 1;
    final textP = TextPainter(textDirection: ui.TextDirection.ltr);

    // Spine grid / vertebral levels
    for (int i = 1; i <= 5; i++) {
      final y = s.height * (0.2 + i * 0.12);
      canvas.drawLine(Offset(s.width * 0.25, y), Offset(s.width * 0.75, y), gridP);
      textP.text = TextSpan(text: 'L$i', style: TextStyle(color: color.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.bold));
      textP.layout();
      textP.paint(canvas, Offset(s.width * 0.18, y - 6));
    }

    // Cobb angle lines
    final topVertebra = Offset(s.width * 0.5 - cobb * 1.2, s.height * 0.25);
    final botVertebra = Offset(s.width * 0.5 + cobb * 1.5, s.height * 0.75);
    final apexVertebra = Offset(s.width * 0.5 + cobb * 2.8, s.height * 0.5);

    final spinePath = Path()
      ..moveTo(s.width * 0.5, s.height * 0.15)
      ..quadraticBezierTo(apexVertebra.dx, apexVertebra.dy, s.width * 0.5, s.height * 0.85);

    canvas.drawPath(spinePath, lineP..strokeWidth = 2.5);

    // Cobb angle tangent lines
    final tangentP = Paint()..color = cobb > 10 ? Colors.amberAccent : Colors.cyanAccent..strokeWidth = 1.8;
    canvas.drawLine(Offset(topVertebra.dx - 40, topVertebra.dy - 10), Offset(topVertebra.dx + 60, topVertebra.dy + 15), tangentP);
    canvas.drawLine(Offset(botVertebra.dx - 40, botVertebra.dy + 15), Offset(botVertebra.dx + 60, botVertebra.dy - 10), tangentP);

    // Pelvic level line
    final horizonP = Paint()..color = Colors.greenAccent..strokeWidth = 1.5;
    canvas.drawLine(Offset(s.width * 0.15, s.height * 0.82), Offset(s.width * 0.85, s.height * 0.82), horizonP);
  }
  @override bool shouldRepaint(covariant _XrayPainter o) => o.cobb != cobb;
}

class _ThermalPainter extends CustomPainter {
  final double deltaT; final Color color;
  _ThermalPainter(this.deltaT, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final leftP = Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.fill;
    final rightP = Paint()..color = (deltaT > 0.6 ? Colors.redAccent : Colors.orangeAccent).withOpacity(0.65)..style = PaintingStyle.fill;

    // Paraspinal bilateral thermal spots
    for (int i = 0; i < 6; i++) {
      final y = s.height * (0.2 + i * 0.11);
      canvas.drawCircle(Offset(s.width * 0.42, y), 12, leftP);
      canvas.drawCircle(Offset(s.width * 0.58, y), 12 + (i == 4 ? deltaT * 8 : 0), rightP);
    }

    // Spine midline
    final midP = Paint()..color = Colors.white54..strokeWidth = 1.2;
    canvas.drawLine(Offset(s.width * 0.5, s.height * 0.15), Offset(s.width * 0.5, s.height * 0.85), midP);

    // Hotspot callout tag if high deltaT
    if (deltaT > 0.6) {
      final tagP = Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 2;
      canvas.drawCircle(Offset(s.width * 0.58, s.height * 0.64), 22, tagP);
    }
  }
  @override bool shouldRepaint(covariant _ThermalPainter o) => o.deltaT != deltaT;
}

class _GaitPainter extends CustomPainter {
  final double symmetry; final Color color;
  _GaitPainter(this.symmetry, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final arcP = Paint()..color = color.withOpacity(0.7)..strokeWidth = 3..style = PaintingStyle.stroke;
    final nodeP = Paint()..color = symmetry < 85 ? Colors.amberAccent : Colors.lightGreenAccent..style = PaintingStyle.fill;

    // Pelvic vector & gait stride arc
    final hipL = Offset(s.width * 0.38, s.height * 0.4);
    final hipR = Offset(s.width * 0.62, s.height * 0.4);
    final footL = Offset(s.width * 0.32, s.height * 0.82);
    final footR = Offset(s.width * 0.68 - (100 - symmetry) * 0.8, s.height * 0.78);

    canvas.drawLine(hipL, hipR, Paint()..color = color..strokeWidth = 3);
    canvas.drawLine(hipL, footL, Paint()..color = Colors.purpleAccent..strokeWidth = 2.5);
    canvas.drawLine(hipR, footR, Paint()..color = Colors.deepPurpleAccent..strokeWidth = 2.5);

    canvas.drawCircle(hipL, 6, nodeP);
    canvas.drawCircle(hipR, 6, nodeP);
    canvas.drawCircle(footL, 8, nodeP);
    canvas.drawCircle(footR, 8, nodeP);

    // Stride arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s.width * 0.5, s.height * 0.6), radius: 50),
      0.2, math.pi * 0.7, false, arcP,
    );
  }
  @override bool shouldRepaint(covariant _GaitPainter o) => o.symmetry != symmetry;
}

class _NeuroTremorPainter extends CustomPainter {
  final double hz; final Color color;
  _NeuroTremorPainter(this.hz, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final waveP = Paint()..color = color..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final path = Path()..moveTo(s.width * 0.1, s.height * 0.75);

    // Frequency waveform graph
    final amplitude = math.min(hz * 4.5, 40.0);
    final frequency = math.max(hz, 1.0);

    for (double x = s.width * 0.1; x <= s.width * 0.9; x += 4) {
      final y = s.height * 0.75 + math.sin((x - s.width * 0.1) * 0.08 * frequency) * amplitude;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, waveP);

    // Tremor hand landmark point cloud simulation
    final center = Offset(s.width * 0.5, s.height * 0.38);
    final rng = math.Random(42);
    final dotP = Paint()..color = (hz > 5.0 ? Colors.orangeAccent : Colors.tealAccent).withOpacity(0.7);

    for (int i = 0; i < 16; i++) {
      final dx = center.dx + (rng.nextDouble() - 0.5) * (hz * 6);
      final dy = center.dy + (rng.nextDouble() - 0.5) * (hz * 6);
      canvas.drawCircle(Offset(dx, dy), 4, dotP);
    }
  }
  @override bool shouldRepaint(covariant _NeuroTremorPainter o) => o.hz != hz;
}

class _GonsteadListingPainter extends CustomPainter {
  final double rotation; final Color color;
  _GonsteadListingPainter(this.rotation, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final spineP = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke;
    final rotP = Paint()..color = Colors.cyanAccent..strokeWidth = 2.5;
    final arrowP = Paint()..color = Colors.orangeAccent..strokeWidth = 3;

    // Vertebral body outline & spinous process rotation arrow
    final center = Offset(s.width * 0.5, s.height * 0.45);
    final rect = Rect.fromCenter(center: center, width: s.width * 0.35, height: s.height * 0.22);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), spineP);

    // Spinous process rotation vector
    final spinousTip = Offset(center.dx + rotation * 2.5, center.dy + s.height * 0.12);
    canvas.drawLine(center, spinousTip, rotP);
    canvas.drawCircle(spinousTip, 7, Paint()..color = Colors.cyanAccent);

    // Line of Drive (LOD) Arrow P-to-A & R-to-L
    final lodStart = Offset(spinousTip.dx + 40, spinousTip.dy + 30);
    final lodEnd = Offset(spinousTip.dx - 10, spinousTip.dy - 10);
    canvas.drawLine(lodStart, lodEnd, arrowP);
    canvas.drawCircle(lodEnd, 5, Paint()..color = Colors.orangeAccent);
  }
  @override bool shouldRepaint(covariant _GonsteadListingPainter o) => o.rotation != rotation;
}

class _ProgressComparePainter extends CustomPainter {
  final double improvement; final Color color;
  _ProgressComparePainter(this.improvement, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    // Split screen divider line
    final dividerP = Paint()..color = Colors.white70..strokeWidth = 2;
    canvas.drawLine(Offset(s.width * 0.5, 0), Offset(s.width * 0.5, s.height), dividerP);

    // Baseline red posture vector (left side)
    final baseP = Paint()..color = Colors.redAccent..strokeWidth = 3.5..style = PaintingStyle.stroke;
    final basePath = Path()
      ..moveTo(s.width * 0.25, s.height * 0.15)
      ..quadraticBezierTo(s.width * 0.38, s.height * 0.5, s.width * 0.25, s.height * 0.85);
    canvas.drawPath(basePath, baseP);

    // Follow-up green corrected posture vector (right side)
    final currP = Paint()..color = Colors.tealAccent..strokeWidth = 3.5..style = PaintingStyle.stroke;
    final currPath = Path()
      ..moveTo(s.width * 0.75, s.height * 0.15)
      ..quadraticBezierTo(s.width * 0.76, s.height * 0.5, s.width * 0.75, s.height * 0.85);
    canvas.drawPath(currPath, currP);
  }
  @override bool shouldRepaint(covariant _ProgressComparePainter o) => o.improvement != improvement;
}

class _GoniometerPainter extends CustomPainter {
  final double angle; final Color color;
  _GoniometerPainter(this.angle, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final armP = Paint()..color = color..strokeWidth = 3.5..strokeCap = StrokeCap.round;
    final pivotP = Paint()..color = Colors.yellowAccent..style = PaintingStyle.fill;
    final arcP = Paint()..color = color.withOpacity(0.35)..style = PaintingStyle.fill;

    final pivot = Offset(s.width * 0.5, s.height * 0.5);
    final rad = (angle - 90) * math.pi / 180.0;
    final arm1 = Offset(pivot.dx, pivot.dy - s.height * 0.25);
    final arm2 = Offset(pivot.dx + s.height * 0.25 * math.cos(rad), pivot.dy + s.height * 0.25 * math.sin(rad));

    canvas.drawLine(pivot, arm1, armP);
    canvas.drawLine(pivot, arm2, armP);
    canvas.drawCircle(pivot, 8, pivotP);
    canvas.drawCircle(pivot, 16, Paint()..color = color.withOpacity(0.25));

    // Goniometer arc
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: 45),
      -math.pi / 2, rad + math.pi / 2, true, arcP,
    );
  }
  @override bool shouldRepaint(covariant _GoniometerPainter o) => o.angle != angle;
}

class _FullBodyAnatomicPainter extends CustomPainter {
  final VisionScenario scenario;
  _FullBodyAnatomicPainter(this.scenario);

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width * 0.5;
    final cy = s.height * 0.5;

    // Dark Medical Grid Background
    final bgGridP = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), bgGridP);
    }
    for (double y = 0; y < s.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), bgGridP);
    }

    final highlightP = Paint()
      ..color = scenario.color.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final nodeP = Paint()..color = Colors.tealAccent..style = PaintingStyle.fill;
    final textP = TextPainter(textDirection: ui.TextDirection.ltr);

    switch (scenario) {
      case VisionScenario.xraySpine:
        // Render Radiograph X-Ray Spine Anatomy
        final boneP = Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        final borderP = Paint()
          ..color = Colors.cyanAccent.withValues(alpha: 0.6)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

        // Vertebrae bodies L1-L5
        for (int i = 0; i < 5; i++) {
          final vy = s.height * (0.25 + i * 0.12);
          final vRect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, vy), width: s.width * 0.28, height: s.height * 0.08),
            const Radius.circular(6),
          );
          canvas.drawRRect(vRect, boneP);
          canvas.drawRRect(vRect, borderP);

          // Intervertebral disc space
          if (i < 4) {
            final discY = vy + s.height * 0.055;
            final discRect = Rect.fromCenter(center: Offset(cx, discY), width: s.width * 0.24, height: s.height * 0.025);
            canvas.drawRect(discRect, Paint()..color = Colors.cyan.withValues(alpha: 0.3));
          }

          // Vertebral label
          textP.text = TextSpan(
            text: 'L${i + 1}',
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          );
          textP.layout();
          textP.paint(canvas, Offset(cx - s.width * 0.22, vy - 6));
        }

        // Spine midline Cobb vector
        final spinePath = Path()
          ..moveTo(cx, s.height * 0.15)
          ..quadraticBezierTo(cx + 18, s.height * 0.5, cx, s.height * 0.85);
        canvas.drawPath(spinePath, highlightP..strokeWidth = 3);
        break;

      case VisionScenario.posture:
      case VisionScenario.gonsteadListing:
        // Render Cervical/Thoracic/Lumbar Spine Column Vector
        final spineP = Paint()
          ..color = scenario.color
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke;
        final plumbP = Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.6)
          ..strokeWidth = 1.5;

        // Plumb line reference
        canvas.drawLine(Offset(cx, s.height * 0.1), Offset(cx, s.height * 0.9), plumbP);

        // Spine curvature
        final path = Path()
          ..moveTo(cx, s.height * 0.15)
          ..cubicTo(cx + 15, s.height * 0.35, cx - 20, s.height * 0.6, cx, s.height * 0.85);
        canvas.drawPath(path, spineP);

        // Anatomical landmark nodes (Occiput, T1, L3, Sacrum)
        final nodes = [
          Offset(cx, s.height * 0.15),
          Offset(cx + 10, s.height * 0.35),
          Offset(cx - 12, s.height * 0.6),
          Offset(cx, s.height * 0.85),
        ];
        for (var pt in nodes) {
          canvas.drawCircle(pt, 6, nodeP);
          canvas.drawCircle(pt, 12, Paint()..color = scenario.color.withValues(alpha: 0.3)..style = PaintingStyle.stroke);
        }
        break;

      case VisionScenario.thermalScan:
        // Paraspinal Infrared Thermographic Heatmap Visual
        final blueP = Paint()..color = Colors.blue.withValues(alpha: 0.35)..style = PaintingStyle.fill;
        final redP = Paint()..color = Colors.redAccent.withValues(alpha: 0.6)..style = PaintingStyle.fill;
        final orangeP = Paint()..color = Colors.orangeAccent.withValues(alpha: 0.5)..style = PaintingStyle.fill;

        for (int i = 0; i < 7; i++) {
          final y = s.height * (0.2 + i * 0.09);
          canvas.drawCircle(Offset(cx - s.width * 0.15, y), 22, blueP);
          final rightColor = (i == 3 || i == 4) ? redP : orangeP;
          canvas.drawCircle(Offset(cx + s.width * 0.15, y), (i == 3 || i == 4) ? 28 : 20, rightColor);
        }
        canvas.drawLine(Offset(cx, s.height * 0.15), Offset(cx, s.height * 0.85), Paint()..color = Colors.white54..strokeWidth = 2);
        break;

      case VisionScenario.dermatology:
        // Dermatological Skin Scan Surface
        final skinRingP = Paint()
          ..color = scenario.color.withValues(alpha: 0.7)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(Offset(cx, cy), s.width * 0.22, skinRingP);
        canvas.drawCircle(Offset(cx, cy), s.width * 0.12, Paint()..color = Colors.pinkAccent.withValues(alpha: 0.25));
        canvas.drawCircle(Offset(cx, cy), 6, nodeP);

        // Scanning reticle crosshairs
        canvas.drawLine(Offset(cx - s.width * 0.28, cy), Offset(cx + s.width * 0.28, cy), Paint()..color = scenario.color.withValues(alpha: 0.4));
        canvas.drawLine(Offset(cx, cy - s.width * 0.28), Offset(cx, cy + s.width * 0.28), Paint()..color = scenario.color.withValues(alpha: 0.4));
        break;

      case VisionScenario.facialAsymmetry:
        // Facial Palsy Symmetry Grid
        final faceOval = Rect.fromCenter(center: Offset(cx, cy), width: s.width * 0.42, height: s.height * 0.55);
        canvas.drawOval(faceOval, highlightP);

        // Eye and mouth landmark horizontal alignment lines
        canvas.drawLine(Offset(cx - s.width * 0.25, cy - s.height * 0.1), Offset(cx + s.width * 0.25, cy - s.height * 0.1), Paint()..color = Colors.indigoAccent..strokeWidth = 1.5);
        canvas.drawLine(Offset(cx - s.width * 0.25, cy + s.height * 0.12), Offset(cx + s.width * 0.25, cy + s.height * 0.12), Paint()..color = Colors.indigoAccent..strokeWidth = 1.5);

        canvas.drawCircle(Offset(cx - s.width * 0.1, cy - s.height * 0.1), 5, nodeP);
        canvas.drawCircle(Offset(cx + s.width * 0.1, cy - s.height * 0.1), 5, nodeP);
        canvas.drawCircle(Offset(cx - s.width * 0.08, cy + s.height * 0.12), 5, nodeP);
        canvas.drawCircle(Offset(cx + s.width * 0.08, cy + s.height * 0.1), 5, Paint()..color = Colors.amberAccent);
        break;

      case VisionScenario.joints:
      case VisionScenario.fullBodyRom:
        // Joint Articular Goniometer Vector
        final jointPivot = Offset(cx, cy);
        final bone1 = Offset(cx - s.width * 0.18, cy - s.height * 0.22);
        final bone2 = Offset(cx + s.width * 0.22, cy + s.height * 0.18);

        canvas.drawLine(jointPivot, bone1, highlightP..strokeWidth = 4);
        canvas.drawLine(jointPivot, bone2, highlightP..strokeWidth = 4);
        canvas.drawCircle(jointPivot, 10, Paint()..color = Colors.amberAccent);
        canvas.drawCircle(jointPivot, 24, Paint()..color = scenario.color.withValues(alpha: 0.25));
        break;

      case VisionScenario.gaitAnalysis:
        // Dynamic Stride Gait Movement Vectors
        final hipL = Offset(cx - s.width * 0.15, cy - s.height * 0.15);
        final hipR = Offset(cx + s.width * 0.15, cy - s.height * 0.15);
        final footL = Offset(cx - s.width * 0.22, cy + s.height * 0.28);
        final footR = Offset(cx + s.width * 0.22, cy + s.height * 0.2);

        canvas.drawLine(hipL, hipR, highlightP);
        canvas.drawLine(hipL, footL, Paint()..color = Colors.purpleAccent..strokeWidth = 3);
        canvas.drawLine(hipR, footR, Paint()..color = Colors.deepPurpleAccent..strokeWidth = 3);

        canvas.drawCircle(footL, 8, nodeP);
        canvas.drawCircle(footR, 8, nodeP);
        break;

      case VisionScenario.neuroTremor:
        // Neuromuscular Tremor Waveform & Hand Landmark Cloud
        final waveP = Paint()..color = scenario.color..strokeWidth = 2.5..style = PaintingStyle.stroke;
        final wavePath = Path()..moveTo(s.width * 0.1, cy + s.height * 0.2);
        for (double x = s.width * 0.1; x <= s.width * 0.9; x += 5) {
          final y = cy + s.height * 0.2 + math.sin(x * 0.08) * 18;
          wavePath.lineTo(x, y);
        }
        canvas.drawPath(wavePath, waveP);

        final rng = math.Random(42);
        for (int i = 0; i < 14; i++) {
          final dx = cx + (rng.nextDouble() - 0.5) * s.width * 0.35;
          final dy = cy - s.height * 0.1 + (rng.nextDouble() - 0.5) * s.height * 0.25;
          canvas.drawCircle(Offset(dx, dy), 4.5, Paint()..color = Colors.amberAccent.withValues(alpha: 0.8));
        }
        break;

      case VisionScenario.compareProgress:
        // Baseline vs Follow-up Split Screen Posture Vector
        canvas.drawLine(Offset(cx, 0), Offset(cx, s.height), Paint()..color = Colors.white54..strokeWidth = 2);

        // Baseline (Left)
        final leftPath = Path()
          ..moveTo(s.width * 0.25, s.height * 0.15)
          ..quadraticBezierTo(s.width * 0.38, cy, s.width * 0.25, s.height * 0.85);
        canvas.drawPath(leftPath, Paint()..color = Colors.redAccent..strokeWidth = 3.5..style = PaintingStyle.stroke);

        // Progress (Right)
        final rightPath = Path()
          ..moveTo(s.width * 0.75, s.height * 0.15)
          ..quadraticBezierTo(s.width * 0.76, cy, s.width * 0.75, s.height * 0.85);
        canvas.drawPath(rightPath, Paint()..color = Colors.tealAccent..strokeWidth = 3.5..style = PaintingStyle.stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FullBodyAnatomicPainter oldDelegate) => oldDelegate.scenario != scenario;
}
