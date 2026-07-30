import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';

import '../../models/appointment.dart';
import '../../models/payment.dart';

Future<Uint8List> generatePatientReportPdf(Appointment appointment) async {
  final doc = pw.Document();

  // Load logo and digital stamp from assets
  Uint8List? logoBytes;
  Uint8List? stampBytes;
  try {
    logoBytes = (await rootBundle.load(
      'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
    )).buffer.asUint8List();
  } catch (_) {
    try {
      logoBytes = (await rootBundle.load(
        'assets/dr-bashir-photo.jpeg',
      )).buffer.asUint8List();
    } catch (_) {}
  }

  try {
    stampBytes = (await rootBundle.load(
      'assets/DIGITAL_STAMP.png',
    )).buffer.asUint8List();
  } catch (_) {}

  final clinicName = 'GONSTEAD CHIROPRACTIC TREATMENT';
  final clinicAddress =
      'Tehsil Road, Near Peshawar Model School, Nowshera City, KPK.';
  final clinicDoctor = 'DR. BASHIR AHMAD';
  final clinicPhone = '+92 304 6996267';

  final primaryColor = PdfColor.fromHex('#0E7490');
  final secondaryColor = PdfColor.fromHex('#0F172A');
  final accentColor = PdfColor.fromHex('#F8FAFC');
  final borderColor = PdfColor.fromHex('#E2E8F0');
  final textColor = PdfColor.fromHex('#1E293B');
  final labelColor = PdfColor.fromHex('#64748B');

  final formattedDate = appointment.scheduledAt != null
      ? DateFormat(
          'EEEE, MMMM dd, yyyy',
        ).format(appointment.scheduledAt!.toLocal())
      : appointment.time;
  final formattedTime = appointment.scheduledAt != null
      ? DateFormat('hh:mm a').format(appointment.scheduledAt!.toLocal())
      : 'N/A';

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        buildBackground: (context) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: -0.5,
                child: pw.Opacity(
                  opacity: 0.04,
                  child: pw.Text(
                    'GONSTEAD CHIROPRACTIC\nTREATMENT',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 60,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      header: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Top Accent Bar
            pw.Container(
              height: 4,
              decoration: pw.BoxDecoration(
                color: primaryColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.SizedBox(height: 8),
            // Clinic Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      if (logoBytes != null)
                        pw.Container(
                          width: 50,
                          height: 50,
                          decoration: pw.BoxDecoration(
                            shape: pw.BoxShape.circle,
                            image: pw.DecorationImage(
                              image: pw.MemoryImage(logoBytes),
                              fit: pw.BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        pw.Container(
                          width: 50,
                          height: 50,
                          decoration: pw.BoxDecoration(
                            color: primaryColor,
                            shape: pw.BoxShape.circle,
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            'GCT',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              _cleanText(clinicName),
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: secondaryColor,
                              ),
                            ),
                            pw.SizedBox(height: 1),
                            pw.Text(
                              _cleanText('Specialized Spine & Posture Care'),
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontStyle: pw.FontStyle.italic,
                                color: labelColor,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              _cleanText(clinicAddress),
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: labelColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      _cleanText(clinicDoctor),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    pw.Text(
                      _cleanText('Chiropractic Specialist'),
                      style: pw.TextStyle(fontSize: 8, color: labelColor),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      _cleanText('Mob: $clinicPhone'),
                      style: pw.TextStyle(fontSize: 8, color: labelColor),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(height: 1, thickness: 1, color: borderColor),
            pw.SizedBox(height: 10),
          ],
        );
      },
      footer: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Signature & Sign-off
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Attending Practitioner',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: labelColor,
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(
                      width: 120,
                      height: 1,
                      color: const PdfColor(
                        100 / 255,
                        116 / 255,
                        139 / 255,
                        0.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _cleanText(clinicDoctor),
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    pw.Text(
                      _cleanText('Chiropractic Specialist'),
                      style: pw.TextStyle(fontSize: 7.5, color: labelColor),
                    ),
                  ],
                ),
                if (stampBytes != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10, right: -10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                          width: 80,
                          height: 80,
                          child: pw.Image(pw.MemoryImage(stampBytes)),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          _cleanText('Digitally Verified Report'),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#10B981'),
                          ),
                        ),
                        pw.Text(
                          _cleanText(
                            'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now().toLocal())}',
                          ),
                          style: pw.TextStyle(fontSize: 6.5, color: labelColor),
                        ),
                      ],
                    ),
                  )
                else
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          _cleanText('Document Verified'),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#10B981'),
                          ),
                        ),
                        pw.SizedBox(height: 20),
                        pw.Text(
                          _cleanText(
                            'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now().toLocal())}',
                          ),
                          style: pw.TextStyle(fontSize: 7.5, color: labelColor),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(height: 1, thickness: 0.5, color: borderColor),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'This report is generated digitally and verified with a digital doctor stamp. All information is confidential.',
                style: pw.TextStyle(
                  fontSize: 7,
                  color: const PdfColor(100 / 255, 116 / 255, 139 / 255, 0.7),
                ),
              ),
            ),
          ],
        );
      },
      build: (context) {
        return [
          // Report Title Card
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: pw.BoxDecoration(
              color: primaryColor,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'CLINICAL HEALTH REPORT',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  _cleanText('ID: ${appointment.id.toUpperCase()}'),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor(1.0, 1.0, 1.0, 0.8),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),

          // Patient & Appointment Grid Layout
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Patient Details Column
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: accentColor,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: borderColor),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PATIENT INFORMATION',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      _buildDetailRow(
                        'Name',
                        appointment.patientName,
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Phone',
                        appointment.phoneNumber.isNotEmpty
                            ? appointment.phoneNumber
                            : 'N/A',
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Email',
                        appointment.email.isNotEmpty
                            ? appointment.email
                            : 'N/A',
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Profession',
                        appointment.patientProfession.isNotEmpty
                            ? appointment.patientProfession
                            : 'N/A',
                        labelColor,
                        textColor,
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              // Visit Details Column
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: accentColor,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: borderColor),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VISIT INFORMATION',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      _buildDetailRow(
                        'Date',
                        formattedDate,
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Time',
                        formattedTime,
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Treatment',
                        appointment.treatmentType,
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Duration',
                        '${appointment.durationMinutes} minutes',
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Priority',
                        appointment.isEmergency ? 'EMERGENCY' : 'Standard',
                        labelColor,
                        appointment.isEmergency
                            ? PdfColor.fromHex('#EF4444')
                            : textColor,
                        isBoldValue: appointment.isEmergency,
                      ),
                      _buildDetailRow(
                        'Status',
                        appointment.status,
                        labelColor,
                        appointment.status.toLowerCase() == 'confirmed'
                            ? PdfColor.fromHex('#10B981')
                            : textColor,
                        isBoldValue: true,
                      ),
                      if (appointment.treatmentPlanTotalSessions != null)
                        _buildDetailRow(
                          'Session',
                          '${appointment.sessionNumber ?? 1} of ${appointment.treatmentPlanTotalSessions}',
                          labelColor,
                          primaryColor,
                          isBoldValue: true,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),

          // Visit Reason Card
          if (appointment.visitReason.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(width: 4, height: 10, color: primaryColor),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'REASON FOR VISIT',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _cleanText(appointment.visitReason),
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: textColor,
                      lineSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],

          // Clinical Assessment & Vitals Card
          if ((appointment.painLevel != null) ||
              appointment.bloodPressure.isNotEmpty ||
              (appointment.pulseRate != null) ||
              appointment.adjustedSegments.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(width: 4, height: 10, color: primaryColor),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'CLINICAL ASSESSMENT & VITALS',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (appointment.painLevel != null)
                              _buildDetailRow(
                                'Pain Scale',
                                '${appointment.painLevel}/10 (VAS)',
                                labelColor,
                                textColor,
                              ),
                            if (appointment.bloodPressure.isNotEmpty)
                              _buildDetailRow(
                                'Blood Pressure',
                                appointment.bloodPressure,
                                labelColor,
                                textColor,
                              ),
                            if (appointment.pulseRate != null)
                              _buildDetailRow(
                                'Pulse Rate',
                                '${appointment.pulseRate} bpm',
                                labelColor,
                                textColor,
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (appointment.adjustedSegments.isNotEmpty) ...[
                              pw.Text(
                                'ADJUSTED SEGMENTS',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: labelColor,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                _cleanText(appointment.adjustedSegments),
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ] else
                              pw.Text(
                                'No adjustments registered.',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: labelColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],

          // Clinical notes
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F8FAFC'),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: borderColor),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 4,
                      height: 10,
                      color: PdfColor.fromHex('#10B981'),
                    ),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      'CLINICAL NOTES & FINDINGS',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#10B981'),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _cleanText(
                    appointment.patientNote.isNotEmpty
                        ? appointment.patientNote
                        : 'No clinical notes recorded for this visit.',
                  ),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: textColor,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // Recommendations & Care Plan
          if (appointment.prescribedExercises.isNotEmpty ||
              appointment.nextFollowUp.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F0FDFA'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#99F6E4')),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 4,
                        height: 10,
                        color: PdfColor.fromHex('#0D9488'),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'PRACTITIONER CARE PLAN & RECOMMENDATIONS',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0F766E'),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  if (appointment.prescribedExercises.isNotEmpty) ...[
                    pw.Text(
                      'Home Exercises & Posture Tips:',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: labelColor,
                      ),
                    ),
                    pw.Text(
                      _cleanText(appointment.prescribedExercises),
                      style: pw.TextStyle(fontSize: 8.5, color: textColor),
                    ),
                    pw.SizedBox(height: 4),
                  ],
                  if (appointment.nextFollowUp.isNotEmpty) ...[
                    pw.Row(
                      children: [
                        pw.Text(
                          'Recommended Next Follow-up: ',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: labelColor,
                          ),
                        ),
                        pw.Text(
                          _cleanText(appointment.nextFollowUp),
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#0D9488'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],

          // Cancellation Reason Card
          if (appointment.status.toLowerCase() == 'cancelled' &&
              appointment.cancellationReason.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#FEF2F2'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#FCA5A5')),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 4,
                        height: 10,
                        color: PdfColor.fromHex('#EF4444'),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        'CANCELLATION REASON',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#B91C1C'),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _cleanText(appointment.cancellationReason),
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor.fromHex('#991B1B'),
                      lineSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],
        ];
      },
    ),
  );

  return doc.save();
}

pw.Widget _buildDetailRow(
  String label,
  String value,
  PdfColor labelColor,
  PdfColor valueColor, {
  bool isBoldValue = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 60,
          child: pw.Text(
            _cleanText(label),
            style: pw.TextStyle(fontSize: 9, color: labelColor),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            _cleanText(value),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBoldValue
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: valueColor,
            ),
          ),
        ),
      ],
    ),
  );
}

String _cleanText(String text) {
  return text
      .replaceAll('•', '-')
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('”', '"')
      .replaceAll('“', '"')
      .runes
      .map(
        (r) => (r >= 32 && r <= 126) || r == 10 || r == 13
            ? String.fromCharCode(r)
            : '',
      )
      .join('');
}

// ═══════════════════════════════════════════════════════════════════════
// ALL SESSIONS COMPREHENSIVE REPORT
// ═══════════════════════════════════════════════════════════════════════

Future<Uint8List> generateAllSessionsReportPdf(
  List<Appointment> sessions,
) async {
  final doc = pw.Document();

  // Load assets
  Uint8List? logoBytes;
  Uint8List? stampBytes;
  try {
    logoBytes = (await rootBundle.load(
      'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
    )).buffer.asUint8List();
  } catch (_) {
    try {
      logoBytes = (await rootBundle.load(
        'assets/dr-bashir-photo.jpeg',
      )).buffer.asUint8List();
    } catch (_) {}
  }
  try {
    stampBytes = (await rootBundle.load(
      'assets/DIGITAL_STAMP.png',
    )).buffer.asUint8List();
  } catch (_) {}

  const clinicName = 'GONSTEAD CHIROPRACTIC TREATMENT';
  const clinicAddress =
      'Tehsil Road, Near Peshawar Model School, Nowshera City, KPK.';
  const clinicDoctor = 'DR. BASHIR AHMAD';
  const clinicPhone = '+92 304 6996267';

  final primaryColor = PdfColor.fromHex('#0E7490');
  final secondaryColor = PdfColor.fromHex('#0F172A');
  final accentBg = PdfColor.fromHex('#F8FAFC');
  final borderColor = PdfColor.fromHex('#E2E8F0');
  final textColor = PdfColor.fromHex('#1E293B');
  final labelColor = PdfColor.fromHex('#64748B');
  final greenAccent = PdfColor.fromHex('#10B981');
  final amberAccent = PdfColor.fromHex('#D97706');

  // Patient info from first session
  final patient = sessions.first;
  final totalSessions = sessions.length;
  final completedSessions = sessions
      .where((s) => s.status.toLowerCase() == 'completed')
      .length;
  final noShowSessions = sessions
      .where((s) => s.status.toLowerCase() == 'no show')
      .length;
  final cancelledSessions = sessions
      .where((s) => s.status.toLowerCase() == 'cancelled')
      .length;

  // Treatment plan info
  final hasPlan =
      patient.treatmentPlanTotalSessions != null &&
      patient.treatmentPlanTotalSessions! > 0;
  final planTotal = patient.treatmentPlanTotalSessions ?? totalSessions;

  // Shared Header Builder
  pw.Widget buildHeader(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: 4,
          decoration: pw.BoxDecoration(
            color: primaryColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoBytes != null)
                    pw.Container(
                      width: 45,
                      height: 45,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        image: pw.DecorationImage(
                          image: pw.MemoryImage(logoBytes),
                          fit: pw.BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    pw.Container(
                      width: 45,
                      height: 45,
                      decoration: pw.BoxDecoration(
                        color: primaryColor,
                        shape: pw.BoxShape.circle,
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        'GCT',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          _cleanText(clinicName),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: secondaryColor,
                          ),
                        ),
                        pw.Text(
                          _cleanText(clinicAddress),
                          style: pw.TextStyle(fontSize: 7, color: labelColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  _cleanText(clinicDoctor),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                pw.Text(
                  _cleanText('Mob: $clinicPhone'),
                  style: pw.TextStyle(fontSize: 7.5, color: labelColor),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(height: 1, thickness: 0.5, color: borderColor),
        pw.SizedBox(height: 6),
      ],
    );
  }

  // Shared Footer Builder
  pw.Widget buildFooter(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Attending Practitioner',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: labelColor,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  width: 100,
                  height: 1,
                  color: const PdfColor(100 / 255, 116 / 255, 139 / 255, 0.5),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _cleanText(clinicDoctor),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: textColor,
                  ),
                ),
                pw.Text(
                  _cleanText('Chiropractic Specialist'),
                  style: pw.TextStyle(fontSize: 7, color: labelColor),
                ),
              ],
            ),
            if (stampBytes != null)
              pw.Container(
                width: 65,
                height: 65,
                child: pw.Image(pw.MemoryImage(stampBytes)),
              )
            else
              pw.Text(
                _cleanText('Document Verified'),
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: greenAccent,
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(height: 1, thickness: 0.5, color: borderColor),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Confidential - All Sessions Clinical Report',
              style: pw.TextStyle(
                fontSize: 6.5,
                color: const PdfColor(100 / 255, 116 / 255, 139 / 255, 0.7),
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 6.5, color: labelColor),
            ),
          ],
        ),
      ],
    );
  }

  // Build the Report
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        buildBackground: (context) {
          return pw.FullPage(
            ignoreMargins: true,
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: -0.5,
                child: pw.Opacity(
                  opacity: 0.04,
                  child: pw.Text(
                    'GONSTEAD CHIROPRACTIC\nTREATMENT',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 60,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      header: buildHeader,
      footer: buildFooter,
      build: (context) {
        final List<pw.Widget> content = [];

        // Cover Title
        content.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: pw.BoxDecoration(
              color: primaryColor,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'COMPREHENSIVE TREATMENT REPORT',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  _cleanText(
                    'Generated: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                  ),
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: const PdfColor(1, 1, 1, 0.8),
                  ),
                ),
              ],
            ),
          ),
        );
        content.add(pw.SizedBox(height: 12));

        // Patient Profile Card
        content.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: accentBg,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: borderColor),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PATIENT PROFILE',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      _buildDetailRow(
                        'Name',
                        patient.patientName,
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Phone',
                        patient.phoneNumber.isNotEmpty
                            ? patient.phoneNumber
                            : 'N/A',
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Email',
                        patient.email.isNotEmpty ? patient.email : 'N/A',
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Profession',
                        patient.patientProfession.isNotEmpty
                            ? patient.patientProfession
                            : 'N/A',
                        labelColor,
                        textColor,
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: accentBg,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: borderColor),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'TREATMENT OVERVIEW',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      _buildDetailRow(
                        'Total Sessions',
                        '$totalSessions',
                        labelColor,
                        textColor,
                      ),
                      _buildDetailRow(
                        'Completed',
                        '$completedSessions',
                        labelColor,
                        greenAccent,
                        isBoldValue: true,
                      ),
                      if (noShowSessions > 0)
                        _buildDetailRow(
                          'No Shows',
                          '$noShowSessions',
                          labelColor,
                          PdfColor.fromHex('#8B5CF6'),
                          isBoldValue: true,
                        ),
                      if (cancelledSessions > 0)
                        _buildDetailRow(
                          'Cancelled',
                          '$cancelledSessions',
                          labelColor,
                          PdfColor.fromHex('#EF4444'),
                          isBoldValue: true,
                        ),
                      if (hasPlan)
                        _buildDetailRow(
                          'Plan',
                          '$completedSessions of $planTotal completed',
                          labelColor,
                          amberAccent,
                          isBoldValue: true,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        content.add(pw.SizedBox(height: 8));

        // Progress Bar (if treatment plan)
        if (hasPlan) {
          final progressPercent = planTotal > 0
              ? (completedSessions / planTotal)
              : 0.0;
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F0FDFA'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#99F6E4')),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TREATMENT PLAN PROGRESS',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0F766E'),
                        ),
                      ),
                      pw.Text(
                        '${(progressPercent * 100).round()}% Complete',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.ClipRRect(
                    horizontalRadius: 3,
                    verticalRadius: 3,
                    child: pw.Container(
                      height: 8,
                      child: pw.Row(
                        children: [
                          if (progressPercent > 0 &&
                              (progressPercent * 100).round() > 0)
                            pw.Expanded(
                              flex: (progressPercent * 100).round(),
                              child: pw.Container(color: primaryColor),
                            ),
                          if (progressPercent < 1.0 &&
                              ((1.0 - progressPercent) * 100).round() > 0)
                            pw.Expanded(
                              flex: ((1.0 - progressPercent) * 100).round(),
                              child: pw.Container(
                                color: PdfColor.fromHex('#E2E8F0'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '$completedSessions sessions completed',
                        style: pw.TextStyle(fontSize: 7.5, color: labelColor),
                      ),
                      pw.Text(
                        '${(planTotal - completedSessions).clamp(0, planTotal)} remaining',
                        style: pw.TextStyle(fontSize: 7.5, color: labelColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          content.add(pw.SizedBox(height: 12));
        }

        // Divider before sessions
        content.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: pw.BoxDecoration(
              color: secondaryColor,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'SESSION DETAILS',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        );
        content.add(pw.SizedBox(height: 8));

        // Individual Session Cards
        for (int i = 0; i < sessions.length; i++) {
          final s = sessions[i];
          final sessionDate = s.scheduledAt != null
              ? DateFormat('EEE, dd MMM yyyy').format(s.scheduledAt!.toLocal())
              : 'N/A';
          final sessionTime = s.scheduledAt != null
              ? DateFormat('hh:mm a').format(s.scheduledAt!.toLocal())
              : s.time;

          PdfColor statusClr;
          switch (s.status.toLowerCase()) {
            case 'completed':
              statusClr = greenAccent;
              break;
            case 'confirmed':
              statusClr = PdfColor.fromHex('#3B82F6');
              break;
            case 'cancelled':
              statusClr = PdfColor.fromHex('#EF4444');
              break;
            case 'no show':
              statusClr = PdfColor.fromHex('#8B5CF6');
              break;
            default:
              statusClr = amberAccent;
          }

          content.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: accentBg,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Session header row
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: pw.BoxDecoration(
                              color: primaryColor,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text(
                              'SESSION ${s.sessionNumber ?? (i + 1)}',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Text(
                            _cleanText('$sessionDate  |  $sessionTime'),
                            style: pw.TextStyle(fontSize: 8, color: textColor),
                          ),
                        ],
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: pw.BoxDecoration(
                          color: statusClr,
                          borderRadius: pw.BorderRadius.circular(10),
                        ),
                        child: pw.Text(
                          _cleanText(s.status.toUpperCase()),
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(height: 1, thickness: 0.5, color: borderColor),
                  pw.SizedBox(height: 6),

                  // Info grid
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              'Treatment',
                              s.treatmentType,
                              labelColor,
                              textColor,
                            ),
                            _buildDetailRow(
                              'Duration',
                              '${s.durationMinutes} min',
                              labelColor,
                              textColor,
                            ),
                            if (s.painLevel != null)
                              _buildDetailRow(
                                'Pain Level',
                                '${s.painLevel}/10',
                                labelColor,
                                textColor,
                              ),
                            if (s.bloodPressure.isNotEmpty)
                              _buildDetailRow(
                                'BP',
                                s.bloodPressure,
                                labelColor,
                                textColor,
                              ),
                            if (s.pulseRate != null)
                              _buildDetailRow(
                                'Pulse',
                                '${s.pulseRate} bpm',
                                labelColor,
                                textColor,
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (s.adjustedSegments.isNotEmpty) ...[
                              pw.Text(
                                'ADJUSTED SEGMENTS',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: labelColor,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                _cleanText(s.adjustedSegments),
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                            ],
                            if (s.visitReason.isNotEmpty) ...[
                              pw.Text(
                                'VISIT REASON',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: labelColor,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                _cleanText(s.visitReason),
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Care plan
                  if (s.prescribedExercises.isNotEmpty ||
                      s.nextFollowUp.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Divider(height: 1, thickness: 0.5, color: borderColor),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (s.prescribedExercises.isNotEmpty)
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'PRESCRIBED EXERCISES',
                                  style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColor.fromHex('#0F766E'),
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  _cleanText(s.prescribedExercises),
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (s.nextFollowUp.isNotEmpty)
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'FOLLOW-UP',
                                  style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColor.fromHex('#0F766E'),
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  _cleanText(s.nextFollowUp),
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],

                  // Clinical notes
                  if (s.patientNote.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#FEF3C7'),
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(
                          color: PdfColor.fromHex('#FCD34D'),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'CLINICAL NOTES',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: amberAccent,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _cleanText(s.patientNote),
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        // Summary Footer Note
        content.add(pw.SizedBox(height: 8));
        content.add(
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F0FDFA'),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColor.fromHex('#99F6E4')),
            ),
            child: pw.Row(
              children: [
                pw.Container(width: 4, height: 12, color: primaryColor),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    _cleanText(
                      'This comprehensive report contains all $totalSessions session records for patient ${patient.patientName}. '
                      'Report generated on ${DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now())} at ${DateFormat('hh:mm a').format(DateTime.now())}.',
                    ),
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColor.fromHex('#0F766E'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return content;
      },
    ),
  );

  return doc.save();
}

Future<Uint8List> generatePaymentReceiptPdf(Payment payment) async {
  final doc = pw.Document();

  Uint8List? logoBytes;
  try {
    logoBytes = (await rootBundle.load(
      'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
    )).buffer.asUint8List();
  } catch (_) {
    try {
      logoBytes = (await rootBundle.load(
        'assets/dr-bashir-photo.jpeg',
      )).buffer.asUint8List();
    } catch (_) {}
  }

  final clinicName = 'GONSTEAD CHIROPRACTIC TREATMENT';
  final clinicAddress =
      'Tehsil Road, Near Peshawar Model School, Nowshera City, KPK.';
  final clinicDoctor = 'DR. BASHIR AHMAD';
  final clinicPhone = '+92 304 6996267';

  final primaryColor = PdfColor.fromHex('#0E7490');
  final secondaryColor = PdfColor.fromHex('#0F172A');
  final borderColor = PdfColor.fromHex('#E2E8F0');
  final textColor = PdfColor.fromHex('#1E293B');
  final labelColor = PdfColor.fromHex('#64748B');

  final formattedDate = DateFormat(
    'EEEE, MMMM dd, yyyy',
  ).format(payment.paidAt.toLocal());
  final formattedTime = DateFormat('hh:mm a').format(payment.paidAt.toLocal());

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(16),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(height: 3, color: primaryColor),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        clinicName,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: secondaryColor,
                        ),
                      ),
                      pw.Text(
                        'Specialized Spine & Posture Care',
                        style: pw.TextStyle(
                          fontSize: 6,
                          fontStyle: pw.FontStyle.italic,
                          color: labelColor,
                        ),
                      ),
                      pw.Text(
                        clinicAddress,
                        style: pw.TextStyle(fontSize: 6, color: labelColor),
                      ),
                      pw.Text(
                        'Mob: $clinicPhone',
                        style: pw.TextStyle(fontSize: 6, color: labelColor),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'PAYMENT RECEIPT',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    pw.Text(
                      'Receipt No: ${payment.id.substring(0, 8).toUpperCase()}',
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(height: 1, thickness: 0.5, color: borderColor),
            pw.SizedBox(height: 10),

            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: borderColor, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Billed To:',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: labelColor,
                        ),
                      ),
                      pw.Text(
                        'Date & Time:',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        payment.patientName,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      pw.Text(
                        '$formattedDate at $formattedTime',
                        style: pw.TextStyle(fontSize: 8, color: textColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            pw.Table(
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F1F5F9'),
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'DESCRIPTION',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: labelColor,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'AMOUNT (PKR)',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                          color: labelColor,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Chiropractic Session Treatment',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          if (payment.note.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'Notes: ${payment.note}',
                              style: pw.TextStyle(
                                fontSize: 7,
                                color: labelColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        NumberFormat('#,##0').format(payment.amount),
                        style: pw.TextStyle(fontSize: 8, color: textColor),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'Total Amount: ',
                          style: pw.TextStyle(fontSize: 7, color: labelColor),
                        ),
                        pw.Text(
                          NumberFormat('PKR #,##0').format(payment.amount),
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'Amount Paid: ',
                          style: pw.TextStyle(fontSize: 7, color: labelColor),
                        ),
                        pw.Text(
                          NumberFormat('PKR #,##0').format(payment.paidAmount),
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'Remaining Balance: ',
                          style: pw.TextStyle(fontSize: 7, color: labelColor),
                        ),
                        pw.Text(
                          NumberFormat(
                            'PKR #,##0',
                          ).format(payment.amount - payment.paidAmount),
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: (payment.amount - payment.paidAmount) > 0
                                ? PdfColor.fromHex('#DC2626')
                                : PdfColor.fromHex('#16A34A'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(height: 1, thickness: 0.5, color: borderColor),
            pw.SizedBox(height: 8),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Payment Method: ${payment.method}',
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    pw.Text(
                      'Status: ${payment.status.toUpperCase()}',
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                        color: payment.status.toLowerCase() == 'paid'
                            ? PdfColor.fromHex('#16A34A')
                            : PdfColor.fromHex('#DC2626'),
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      width: 50,
                      height: 20,
                      alignment: pw.Alignment.bottomCenter,
                      child: pw.Divider(
                        height: 1,
                        thickness: 0.5,
                        color: labelColor,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Authorized Signature',
                      style: pw.TextStyle(fontSize: 6, color: labelColor),
                    ),
                  ],
                ),
              ],
            ),
            pw.Spacer(),

            pw.Center(
              child: pw.Text(
                'Thank you for choosing Gonstead Chiropractic Treatment!',
                style: pw.TextStyle(
                  fontSize: 7,
                  fontStyle: pw.FontStyle.italic,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}
