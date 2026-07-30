import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/app_preferences.dart';

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────
class NoteTemplate {
  final String id;
  final String name;
  final String category;
  final String body;
  final bool isSoap;
  // SOAP fields (only used when isSoap == true)
  final String soapSubjective;
  final String soapObjective;
  final String soapAssessment;
  final String soapPlan;
  final DateTime createdAt;

  const NoteTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.body,
    this.isSoap = false,
    this.soapSubjective = '',
    this.soapObjective = '',
    this.soapAssessment = '',
    this.soapPlan = '',
    required this.createdAt,
  });

  factory NoteTemplate.fromJson(Map<String, dynamic> json) {
    return NoteTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      body: json['body']?.toString() ?? '',
      isSoap: json['isSoap'] == true,
      soapSubjective: json['soapSubjective']?.toString() ?? '',
      soapObjective: json['soapObjective']?.toString() ?? '',
      soapAssessment: json['soapAssessment']?.toString() ?? '',
      soapPlan: json['soapPlan']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'body': body,
    'isSoap': isSoap,
    'soapSubjective': soapSubjective,
    'soapObjective': soapObjective,
    'soapAssessment': soapAssessment,
    'soapPlan': soapPlan,
    'createdAt': createdAt.toIso8601String(),
  };

  NoteTemplate copyWith({
    String? id,
    String? name,
    String? category,
    String? body,
    bool? isSoap,
    String? soapSubjective,
    String? soapObjective,
    String? soapAssessment,
    String? soapPlan,
    DateTime? createdAt,
  }) {
    return NoteTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      body: body ?? this.body,
      isSoap: isSoap ?? this.isSoap,
      soapSubjective: soapSubjective ?? this.soapSubjective,
      soapObjective: soapObjective ?? this.soapObjective,
      soapAssessment: soapAssessment ?? this.soapAssessment,
      soapPlan: soapPlan ?? this.soapPlan,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Renders the template to a full plain text string (for inserting into the note body).
  String get fullText {
    if (isSoap) {
      final parts = <String>[];
      if (soapSubjective.isNotEmpty) parts.add('S: $soapSubjective');
      if (soapObjective.isNotEmpty) parts.add('O: $soapObjective');
      if (soapAssessment.isNotEmpty) parts.add('A: $soapAssessment');
      if (soapPlan.isNotEmpty) parts.add('P: $soapPlan');
      return parts.join('\n');
    }
    return body;
  }
}

// ─────────────────────────────────────────────
// Built-in default templates
// ─────────────────────────────────────────────
final List<NoteTemplate> kBuiltInTemplates = [
  NoteTemplate(
    id: '__builtin_routine_adjustment',
    name: 'Routine Adjustment',
    category: 'Spine',
    body: '',
    isSoap: true,
    soapSubjective: 'Patient reports mild lower back stiffness. No acute pain.',
    soapObjective: 'Restricted motion at L4-L5. Tenderness on palpation.',
    soapAssessment: 'Subluxation complex at lumbar spine.',
    soapPlan:
        'Gonstead adjustment applied at L4-L5. Ice pack recommended. Reassess in 1 week.',
    createdAt: DateTime(2024),
  ),
  NoteTemplate(
    id: '__builtin_cervical_adjustment',
    name: 'Cervical Adjustment',
    category: 'Spine',
    body: '',
    isSoap: true,
    soapSubjective: 'Patient complains of neck stiffness and headache.',
    soapObjective: 'Restricted cervical ROM. Tenderness at C3-C5.',
    soapAssessment: 'Cervical subluxation with secondary headache.',
    soapPlan:
        'Cervical adjustment at C3-C5. Heat therapy. Stretching exercises provided.',
    createdAt: DateTime(2024),
  ),
  NoteTemplate(
    id: '__builtin_first_visit',
    name: 'First Visit Intake',
    category: 'General',
    body: '',
    isSoap: true,
    soapSubjective:
        'New patient presenting with chief complaint of [describe complaint]. Onset [duration] ago.',
    soapObjective:
        'Full postural assessment performed. Spinal palpation reveals [findings].',
    soapAssessment:
        'Initial subluxation pattern identified. X-rays [ordered/reviewed].',
    soapPlan:
        'Initiate care plan. Follow up in 3 days. Patient education on spinal hygiene.',
    createdAt: DateTime(2024),
  ),
  NoteTemplate(
    id: '__builtin_posture_correction',
    name: 'Posture Correction',
    category: 'Posture',
    body:
        'Postural assessment completed. Forward head posture noted (+2.5 cm anterior displacement). '
        'Corrective exercises prescribed: chin tucks x15 reps, wall angels x10. '
        'Ergonomic advice given for workstation setup. Review in 2 weeks.',
    isSoap: false,
    createdAt: DateTime(2024),
  ),
  NoteTemplate(
    id: '__builtin_recovery_follow_up',
    name: 'Recovery Follow-Up',
    category: 'Recovery',
    body: '',
    isSoap: true,
    soapSubjective:
        'Patient reports [improvement/no change/worsening] since last visit. Pain level [0-10].',
    soapObjective: 'ROM [improved/unchanged]. Reduced tenderness at [region].',
    soapAssessment: 'Responding [well/partially] to treatment plan.',
    soapPlan:
        'Continue current protocol. [Adjust care plan if needed]. Next visit: [date].',
    createdAt: DateTime(2024),
  ),
  NoteTemplate(
    id: '__builtin_discharge',
    name: 'Discharge Summary',
    category: 'General',
    body:
        'Patient has completed the care plan and achieved treatment goals. '
        'Significant improvement in ROM and pain levels (VAS from [x] to [y]). '
        'Maintenance care recommended every [4-6 weeks]. '
        'Home exercise program provided. Patient discharged in good condition.',
    isSoap: false,
    createdAt: DateTime(2024),
  ),
];

// ─────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────
class NoteTemplateRepository {
  NoteTemplateRepository() : _prefsFuture = AppPreferences.instance.prefs;

  final Future<SharedPreferences> _prefsFuture;
  static const String _key = 'clinic_note_templates';

  static List<NoteTemplate>? _cache;

  Future<List<NoteTemplate>> loadTemplates() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return List.unmodifiable(_cache!);
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _cache = decoded
          .map(
            (e) => NoteTemplate.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('Error loading templates: $e');
      _cache = [];
    }
    return List.unmodifiable(_cache!);
  }

  Future<void> _persist(List<NoteTemplate> templates) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
      _key,
      jsonEncode(templates.map((t) => t.toJson()).toList()),
    );
    _cache = List.unmodifiable(templates);
  }

  Future<void> saveTemplate(NoteTemplate template) async {
    _cache = null;
    final existing = await loadTemplates();
    await _persist([...existing, template]);
  }

  Future<void> updateTemplate(NoteTemplate template) async {
    _cache = null;
    final existing = await loadTemplates();
    final updated = existing
        .map((t) => t.id == template.id ? template : t)
        .toList();
    await _persist(updated);
  }

  Future<void> deleteTemplate(String id) async {
    _cache = null;
    final existing = await loadTemplates();
    await _persist(existing.where((t) => t.id != id).toList());
  }

  /// Returns built-in + user-created templates combined.
  Future<List<NoteTemplate>> allTemplates() async {
    final user = await loadTemplates();
    return [...kBuiltInTemplates, ...user];
  }
}
