import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../utils/import_export_service.dart';
import '../../services/app_preferences.dart';
import 'package:flutter/services.dart';

import '../shared/widgets/app_shell_scaffold.dart';
import '../shared/widgets/premium_card.dart';
import 'clinical_notes_repository.dart';
import 'note_template_repository.dart';
import '../appointments/appointment_repository.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/repository_providers.dart';
import '../../services/notification_service.dart';

class ClinicalNotesScreen extends ConsumerStatefulWidget {
  const ClinicalNotesScreen({super.key});

  @override
  ConsumerState<ClinicalNotesScreen> createState() => _ClinicalNotesScreenState();
}

class _ClinicalNotesScreenState extends ConsumerState<ClinicalNotesScreen> {
  ClinicalNotesRepository get _repository => ref.read(clinicalNotesRepositoryProvider);
  NoteTemplateRepository get _templateRepository => ref.read(noteTemplateRepositoryProvider);

  final _patientController = TextEditingController();
  final _noteController = TextEditingController();
  final _searchController = TextEditingController();

  final _soapSubjectiveController = TextEditingController();
  final _soapObjectiveController = TextEditingController();
  final _soapAssessmentController = TextEditingController();
  final _soapPlanController = TextEditingController();

  bool _useSoap = true;
  final _formKey = GlobalKey<FormState>();
  final Uuid _uuid = const Uuid();

  List<ClinicalNote> _notes = [];
  List<NoteTemplate> _templates = [];
  List<String> _patientSuggestions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCategory = 'General';
  String _selectedDuration = 'All';
  ClinicalNote? _editingNote;

  static const _categories = ['General', 'Spine', 'Posture', 'Recovery', 'Medication'];
  static const _categoryColors = [
    Color(0xFF6366F1),
    Color(0xFF0A6BE8),
    Color(0xFF00A86B),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B)
  ];
  static const _categoryIcons = [
    Icons.note_rounded,
    Icons.airline_seat_flat_rounded,
    Icons.accessibility_new_rounded,
    Icons.healing_rounded,
    Icons.medication_rounded
  ];

  // Chiropractic Quick Snippets
  static const Map<String, List<String>> _quickSnippets = {
    'Subjective': [
      'Lower back stiffness',
      'Cervical spine tightness',
      'Headache radiation',
      'Postural fatigue',
      'Sciatic discomfort',
    ],
    'Objective': [
      'Restricted ROM C3-C5',
      'Lumbar subluxation L4-L5',
      'Thoracic tightness T4-T8',
      'Tenderness on palpation',
      'Asymmetric shoulder height',
    ],
    'Assessment': [
      'Cervical subluxation complex',
      'Lumbar subluxation pattern',
      'Postural decompensation',
      'Sacroiliac joint dysfunction',
    ],
    'Plan': [
      'Gonstead adjustment applied',
      'Cervical high-velocity adjustment',
      'Ice protocol 15 mins',
      'Postural ergonomic advice',
      'Reassess in 3 days',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadNotesAndSuggestions();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _patientController.dispose();
    _noteController.dispose();
    _searchController.dispose();
    _soapSubjectiveController.dispose();
    _soapObjectiveController.dispose();
    _soapAssessmentController.dispose();
    _soapPlanController.dispose();
    super.dispose();
  }

  Future<void> _loadNotesAndSuggestions() async {
    try {
      final notes = await _repository.loadNotes();
      final templates = await _templateRepository.allTemplates();
      final appointments = await ref.read(appointmentRepositoryProvider).loadAppointments();
      final names = appointments.map((a) => a.patientName.trim()).where((n) => n.isNotEmpty).toSet().toList();

      if (!mounted) return;
      setState(() {
        _notes = notes;
        _templates = templates;
        _patientSuggestions = names;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportNotes() async {
    try {
      final header = ['Note ID', 'Patient Name', 'Clinical Note', 'Category', 'Created At'];
      final rows = <List<dynamic>>[header];
      for (final note in _notes) {
        rows.add([
          note.id,
          note.patientName,
          note.note,
          note.category,
          DateFormat('yyyy-MM-dd HH:mm').format(note.createdAt),
        ]);
      }

      final success = await ImportExportService.exportExcel(
        context: context,
        defaultFileName: 'gct_clinical_notes.xlsx',
        sheets: {'Clinical Notes': rows},
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clinical notes exported to Excel! 💾')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _importNotes() async {
    try {
      final excel = await ImportExportService.importExcel(context: context);
      if (excel == null) return;

      final rows = ImportExportService.parseSheet(excel: excel, sheetName: 'Clinical Notes');
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No clinical notes sheet found or sheet is empty.')),
          );
        }
        return;
      }

      final List<ClinicalNote> imported = [];
      for (final row in rows) {
        final id = row['Note ID']?.toString() ?? _uuid.v4();
        final patientName = row['Patient Name']?.toString() ?? '';
        final note = row['Clinical Note']?.toString() ?? '';
        final category = row['Category']?.toString() ?? 'General';

        DateTime createdAt;
        final rawDate = row['Created At'];
        if (rawDate != null) {
          createdAt = DateTime.tryParse(rawDate.toString()) ?? DateTime.now();
        } else {
          createdAt = DateTime.now();
        }

        if (patientName.isNotEmpty) {
          imported.add(ClinicalNote(
            id: id,
            patientName: patientName,
            note: note,
            category: category,
            createdAt: createdAt,
          ));
        }
      }

      final prefs = await AppPreferences.instance.prefs;
      await prefs.setString(
        'clinic_clinical_notes',
        jsonEncode(imported.map((item) => item.toJson()).toList()),
      );

      await _loadNotesAndSuggestions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clinical notes imported successfully! 🔄')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    if (!_formKey.currentState!.validate()) return;
    final patientName = _patientController.text.trim();

    String noteText;
    if (_useSoap) {
      final s = _soapSubjectiveController.text.trim();
      final o = _soapObjectiveController.text.trim();
      final a = _soapAssessmentController.text.trim();
      final p = _soapPlanController.text.trim();

      final parts = <String>[];
      if (s.isNotEmpty) parts.add('S: $s');
      if (o.isNotEmpty) parts.add('O: $o');
      if (a.isNotEmpty) parts.add('A: $a');
      if (p.isNotEmpty) parts.add('P: $p');
      noteText = parts.join('\n');
    } else {
      noteText = _noteController.text.trim();
    }

    final category = _selectedCategory;

    if (_editingNote != null) {
      final updatedNote = _editingNote!.copyWith(
        patientName: patientName,
        note: noteText,
        category: category,
      );
      await _repository.updateNote(updatedNote);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clinical Note updated ✅')));
      }
    } else {
      await _repository.saveNote(ClinicalNote(
        id: _uuid.v4(),
        patientName: patientName,
        note: noteText,
        category: category,
        createdAt: DateTime.now(),
      ));

      try {
        await NotificationService().showLocalNotification(
          'Clinical Note Saved 📝',
          'Added a $category note for $patientName.',
          payload: '/notes',
        );
      } catch (e) {
        debugPrint('Note notification failed: $e');
      }
    }

    _clearForm();
    if (mounted) {
      FocusScope.of(context).unfocus();
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
    _loadNotesAndSuggestions();
  }

  void _clearForm() {
    _patientController.clear();
    _noteController.clear();
    _soapSubjectiveController.clear();
    _soapObjectiveController.clear();
    _soapAssessmentController.clear();
    _soapPlanController.clear();
    setState(() {
      _selectedCategory = 'General';
      _useSoap = true;
      _editingNote = null;
    });
  }

  Future<void> _deleteNote(String id) async {
    final note = _notes.firstWhere(
      (n) => n.id == id,
      orElse: () => ClinicalNote(id: '', patientName: 'Unknown', note: '', category: '', createdAt: DateTime.now()),
    );
    await _repository.deleteNote(id);

    try {
      await NotificationService().showLocalNotification(
        'Clinical Note Deleted 🗑️',
        'Deleted note for ${note.patientName}.',
        payload: '/notes',
      );
    } catch (e) {
      debugPrint('Note delete notification failed: $e');
    }

    _loadNotesAndSuggestions();
  }

  void _editNote(ClinicalNote note, {bool openModalIfMobile = true}) {
    final lines = note.note.split('\n');
    String s = '';
    String o = '';
    String a = '';
    String p = '';
    bool foundSoap = false;

    for (final line in lines) {
      if (line.startsWith('S: ')) {
        s = line.substring(3);
        foundSoap = true;
      } else if (line.startsWith('O: ')) {
        o = line.substring(3);
        foundSoap = true;
      } else if (line.startsWith('A: ')) {
        a = line.substring(3);
        foundSoap = true;
      } else if (line.startsWith('P: ')) {
        p = line.substring(3);
        foundSoap = true;
      }
    }

    setState(() {
      _editingNote = note;
      _patientController.text = note.patientName;
      _selectedCategory = note.category;
      _useSoap = foundSoap;

      if (foundSoap) {
        _soapSubjectiveController.text = s;
        _soapObjectiveController.text = o;
        _soapAssessmentController.text = a;
        _soapPlanController.text = p;
        _noteController.clear();
      } else {
        _noteController.text = note.note;
        _soapSubjectiveController.clear();
        _soapObjectiveController.clear();
        _soapAssessmentController.clear();
        _soapPlanController.clear();
      }
    });

    final isWide = MediaQuery.of(context).size.width >= 800;
    if (!isWide && openModalIfMobile) {
      _showAddNoteSheet(context);
    }
  }

  void _appendSnippet(TextEditingController controller, String text) {
    final current = controller.text.trim();
    if (current.isEmpty) {
      controller.text = text;
    } else if (!current.contains(text)) {
      controller.text = '$current, $text';
    }
  }

  int _categoryIndex(String cat) => _categories.indexOf(cat).clamp(0, _categories.length - 1);

  bool _matchesDuration(DateTime date) {
    if (_selectedDuration == 'All') return true;
    final diff = DateTime.now().difference(date).abs();
    if (_selectedDuration == '7 Days') return diff.inDays <= 7;
    if (_selectedDuration == '30 Days') return diff.inDays <= 30;
    if (_selectedDuration == '6 Months') return diff.inDays <= 180;
    return true;
  }

  List<ClinicalNote> get _filteredNotes {
    var result = _notes.where((n) => _matchesDuration(n.createdAt)).toList();
    if (_searchQuery.isEmpty) return result;
    return result.where((n) {
      return n.patientName.toLowerCase().contains(_searchQuery) ||
          n.note.toLowerCase().contains(_searchQuery) ||
          n.category.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // ─────────────────────────────────────────────
  // UI Builders
  // ─────────────────────────────────────────────

  Widget _buildFormContent(ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _editingNote != null ? 'Edit Clinical Note' : 'Create Clinical Note',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
              ),
              if (_editingNote != null)
                TextButton.icon(
                  onPressed: _clearForm,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Cancel Edit'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Patient Name Field with Autocomplete
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              return _patientSuggestions.where((String option) {
                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
              });
            },
            onSelected: (String selection) {
              _patientController.text = selection;
            },
            fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
              if (textController.text != _patientController.text) {
                textController.text = _patientController.text;
              }
              textController.addListener(() {
                _patientController.text = textController.text;
              });
              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: 'Patient Name',
                  hintText: 'Select or enter patient name',
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Patient name is required' : null,
              );
            },
          ),
          const SizedBox(height: 14),

          // Category Selector Pills
          Text('Clinical Category', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_categories.length, (i) {
                final cat = _categories[i];
                final isSelected = _selectedCategory == cat;
                final color = _categoryColors[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    selected: isSelected,
                    showCheckmark: false,
                    avatar: Icon(_categoryIcons[i], size: 14, color: isSelected ? Colors.white : color),
                    label: Text(cat, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : color)),
                    backgroundColor: color.withOpacity(0.08),
                    selectedColor: color,
                    shape: StadiumBorder(side: BorderSide(color: isSelected ? color : color.withOpacity(0.2))),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // SOAP Format Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.notes_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Structured SOAP Format',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _useSoap,
                  activeColor: cs.primary,
                  onChanged: (val) => setState(() => _useSoap = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quick Templates Bar
          if (_templates.isNotEmpty) ...[
            Text('Quick Templates', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _templates.map((t) {
                  final isMatch = t.category == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ActionChip(
                      label: Text(t.name, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: isMatch ? Colors.white : cs.onSurface)),
                      backgroundColor: isMatch ? cs.primary : cs.surfaceContainerHighest.withOpacity(0.4),
                      onPressed: () {
                        setState(() {
                          _selectedCategory = t.category;
                          if (t.isSoap) {
                            _useSoap = true;
                            _soapSubjectiveController.text = t.soapSubjective;
                            _soapObjectiveController.text = t.soapObjective;
                            _soapAssessmentController.text = t.soapAssessment;
                            _soapPlanController.text = t.soapPlan;
                          } else {
                            _useSoap = false;
                            _noteController.text = t.body;
                          }
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // SOAP Fields or Freeform Input
          if (_useSoap) ...[
            _buildSoapField('Subjective (S)', 'Patient symptoms & history', _soapSubjectiveController, cs, Color(0xFF6366F1), _quickSnippets['Subjective']!),
            const SizedBox(height: 10),
            _buildSoapField('Objective (O)', 'Palpation, ROM, findings', _soapObjectiveController, cs, Color(0xFF0A6BE8), _quickSnippets['Objective']!),
            const SizedBox(height: 10),
            _buildSoapField('Assessment (A)', 'Diagnosis, subluxation level', _soapAssessmentController, cs, Color(0xFF00A86B), _quickSnippets['Assessment']!),
            const SizedBox(height: 10),
            _buildSoapField('Plan (P)', 'Adjustment protocol, recommendations', _soapPlanController, cs, Color(0xFF8B5CF6), _quickSnippets['Plan']!),
          ] else ...[
            TextFormField(
              controller: _noteController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Clinical Note Details',
                hintText: 'Enter clinical observations, treatment details, or notes…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => _useSoap ? null : ((v == null || v.trim().isEmpty) ? 'Clinical note text is required' : null),
            ),
          ],
          const SizedBox(height: 16),

          // Save Button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saveNote,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: Icon(_editingNote != null ? Icons.check_circle_rounded : Icons.save_rounded, size: 20),
              label: Text(
                _editingNote != null ? 'Update Clinical Note' : 'Save Clinical Note',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoapField(
    String label,
    String hint,
    TextEditingController controller,
    ColorScheme cs,
    Color badgeColor,
    List<String> snippets,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: badgeColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          maxLines: 2,
          style: GoogleFonts.poppins(fontSize: 12.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 11.5, color: cs.onSurface.withOpacity(0.4)),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(10),
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: snippets.map((s) {
              return Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: InkWell(
                  onTap: () => setState(() => _appendSnippet(controller, s)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outline.withOpacity(0.15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 11, color: cs.primary),
                        const SizedBox(width: 2),
                        Text(s, style: GoogleFonts.poppins(fontSize: 9.5, color: cs.onSurface.withOpacity(0.7))),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBarAndFilters(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search notes or patient name…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () => _searchController.clear())
                : null,
            isDense: true,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withOpacity(0.2),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['All', '7 Days', '30 Days', '6 Months'].map((opt) {
              final isSelected = _selectedDuration == opt;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ChoiceChip(
                  label: Text(opt, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : cs.onSurface.withOpacity(0.7))),
                  selected: isSelected,
                  selectedColor: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest.withOpacity(0.3),
                  shape: StadiumBorder(side: BorderSide(color: isSelected ? cs.primary : cs.outline.withOpacity(0.15))),
                  onSelected: (_) => setState(() => _selectedDuration = opt),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCard(ClinicalNote note, ColorScheme cs) {
    final ci = _categoryIndex(note.category);
    final catColor = _categoryColors[ci % _categoryColors.length];
    final catIcon = _categoryIcons[ci % _categoryIcons.length];

    final lines = note.note.split('\n');
    final soapMap = <String, String>{};
    bool isSoapNote = false;

    for (final line in lines) {
      if (line.startsWith('S: ')) {
        soapMap['S'] = line.substring(3);
        isSoapNote = true;
      } else if (line.startsWith('O: ')) {
        soapMap['O'] = line.substring(3);
        isSoapNote = true;
      } else if (line.startsWith('A: ')) {
        soapMap['A'] = line.substring(3);
        isSoapNote = true;
      } else if (line.startsWith('P: ')) {
        soapMap['P'] = line.substring(3);
        isSoapNote = true;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: PremiumCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: catColor.withOpacity(0.12),
                  child: Icon(catIcon, color: catColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.patientName,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Text(
                            DateFormat('MMM d, y • hh:mm a').format(note.createdAt),
                            style: GoogleFonts.poppins(fontSize: 10, color: cs.onSurface.withOpacity(0.4)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: catColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              note.category.toUpperCase(),
                              style: GoogleFonts.poppins(fontSize: 8.5, fontWeight: FontWeight.w700, color: catColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Popup Context Actions
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 18, color: cs.onSurface.withOpacity(0.5)),
                  onSelected: (val) async {
                    if (val == 'view') {
                      _showViewNoteModal(note);
                    } else if (val == 'edit') {
                      _editNote(note);
                    } else if (val == 'history') {
                      context.push('/patient-history?name=${Uri.encodeComponent(note.patientName)}');
                    } else if (val == 'copy') {
                      Clipboard.setData(ClipboardData(text: note.note));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Note copied to clipboard 📋')),
                      );
                    } else if (val == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Delete Note', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                          content: Text('Delete note for ${note.patientName}?', style: GoogleFonts.poppins()),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: cs.error))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        _deleteNote(note.id);
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'view',
                      child: Row(children: [Icon(Icons.visibility_outlined, size: 16, color: cs.primary), const SizedBox(width: 8), const Text('View Full Note')]),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [Icon(Icons.edit_outlined, size: 16, color: cs.primary), const SizedBox(width: 8), const Text('Edit Note')]),
                    ),
                    PopupMenuItem(
                      value: 'history',
                      child: Row(children: [Icon(Icons.history_rounded, size: 16, color: cs.primary), const SizedBox(width: 8), const Text('Patient History')]),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(children: [Icon(Icons.copy_rounded, size: 16, color: cs.primary), const SizedBox(width: 8), const Text('Copy Note')]),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [Icon(Icons.delete_outline_rounded, size: 16, color: cs.error), const SizedBox(width: 8), Text('Delete', style: TextStyle(color: cs.error))]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Card Body (SOAP rendered cleanly or plain text)
            InkWell(
              onTap: () => _showViewNoteModal(note),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: isSoapNote
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (soapMap.containsKey('S')) _buildSoapCardLine('S', soapMap['S']!, const Color(0xFF6366F1), cs),
                          if (soapMap.containsKey('O')) _buildSoapCardLine('O', soapMap['O']!, const Color(0xFF0A6BE8), cs),
                          if (soapMap.containsKey('A')) _buildSoapCardLine('A', soapMap['A']!, const Color(0xFF00A86B), cs),
                          if (soapMap.containsKey('P')) _buildSoapCardLine('P', soapMap['P']!, const Color(0xFF8B5CF6), cs),
                        ],
                      )
                    : SelectableText(
                        note.note,
                        style: GoogleFonts.poppins(fontSize: 12.5, height: 1.45, color: cs.onSurface.withOpacity(0.8)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showViewNoteModal(ClinicalNote note) {
    final cs = Theme.of(context).colorScheme;
    final ci = _categoryIndex(note.category);
    final catColor = _categoryColors[ci % _categoryColors.length];
    final catIcon = _categoryIcons[ci % _categoryIcons.length];

    final lines = note.note.split('\n');
    final soapMap = <String, String>{};
    bool isSoapNote = false;

    for (final line in lines) {
      if (line.startsWith('S: ')) {
        soapMap['S'] = line.substring(3);
        isSoapNote = true;
      } else if (line.startsWith('O: ')) {
        soapMap['O'] = line.substring(3);
        isSoapNote = true;
      } else if (line.startsWith('A: ')) {
        soapMap['A'] = line.substring(3);
        isSoapNote = true;
      } else if (line.startsWith('P: ')) {
        soapMap['P'] = line.substring(3);
        isSoapNote = true;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: catColor.withOpacity(0.12),
                  child: Icon(catIcon, color: catColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.patientName,
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
                      ),
                      Row(
                        children: [
                          Text(
                            DateFormat('MMMM d, yyyy • hh:mm a').format(note.createdAt),
                            style: GoogleFonts.poppins(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: catColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              note.category.toUpperCase(),
                              style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w800, color: catColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 28),
            Flexible(
              child: SingleChildScrollView(
                child: isSoapNote
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (soapMap.containsKey('S')) _buildSoapDetailBlock('Subjective (S)', soapMap['S']!, const Color(0xFF6366F1), cs),
                          if (soapMap.containsKey('O')) _buildSoapDetailBlock('Objective (O)', soapMap['O']!, const Color(0xFF0A6BE8), cs),
                          if (soapMap.containsKey('A')) _buildSoapDetailBlock('Assessment (A)', soapMap['A']!, const Color(0xFF00A86B), cs),
                          if (soapMap.containsKey('P')) _buildSoapDetailBlock('Plan (P)', soapMap['P']!, const Color(0xFF8B5CF6), cs),
                        ],
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outline.withOpacity(0.1)),
                        ),
                        child: SelectableText(
                          note.note,
                          style: GoogleFonts.poppins(fontSize: 14, height: 1.6, color: cs.onSurface),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: note.note));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Clinical note copied to clipboard 📋')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Note'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editNote(note);
                    },
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit Note'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoapDetailBlock(String title, String text, Color color, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: GoogleFonts.poppins(fontSize: 13.5, height: 1.5, color: cs.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildSoapCardLine(String tag, String text, Color color, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tag,
              style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              text,
              style: GoogleFonts.poppins(fontSize: 12, height: 1.4, color: cs.onSurface.withOpacity(0.85)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddNoteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: _buildFormContent(Theme.of(context).colorScheme),
          ),
        ),
      ),
    ).then((_) {
      if (_editingNote != null) {
        _clearForm();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWideScreen = MediaQuery.of(context).size.width >= 800;
    final filtered = _filteredNotes;

    return AppShellScaffold(
      title: 'Clinical Notes',
      currentRoute: '/notes',
      actions: [
        IconButton(
          icon: const Icon(Icons.bookmarks_outlined),
          onPressed: _showManageTemplatesDialog,
          tooltip: 'Manage Templates',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (val) {
            if (val == 'export') _exportNotes();
            if (val == 'import') _importNotes();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'export',
              child: Row(children: [Icon(Icons.download_rounded, size: 18), SizedBox(width: 8), Text('Export to Excel')]),
            ),
            const PopupMenuItem(
              value: 'import',
              child: Row(children: [Icon(Icons.upload_file_rounded, size: 18), SizedBox(width: 8), Text('Import from Excel')]),
            ),
          ],
        ),
      ],
      floatingActionButton: isWideScreen
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddNoteSheet(context),
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text('New Note', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (isWideScreen) {
                  // Dual Pane View for Desktop / Wide Screens
                  return Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Form Pane
                        SizedBox(
                          width: 380,
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: cs.outline.withOpacity(0.12)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(18.0),
                              child: SingleChildScrollView(
                                child: _buildFormContent(cs),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),

                        // Right Feed Pane
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSearchBarAndFilters(cs),
                              const SizedBox(height: 14),
                              Text(
                                '${filtered.length} Clinical Note${filtered.length != 1 ? 's' : ''}',
                                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.55)),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: filtered.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.assignment_outlined, size: 48, color: cs.onSurface.withOpacity(0.2)),
                                            const SizedBox(height: 12),
                                            Text(
                                              _searchQuery.isNotEmpty ? 'No notes match your search' : 'No clinical notes recorded yet',
                                              style: GoogleFonts.poppins(color: cs.onSurface.withOpacity(0.45)),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: filtered.length,
                                        itemBuilder: (context, idx) => _buildNoteCard(filtered[idx], cs),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  // Mobile Single Column View
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSearchBarAndFilters(cs),
                        const SizedBox(height: 14),
                        Text(
                          '${filtered.length} Clinical Note${filtered.length != 1 ? 's' : ''}',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.55)),
                        ),
                        const SizedBox(height: 10),
                        filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 40.0),
                                  child: Column(
                                    children: [
                                      Icon(Icons.assignment_outlined, size: 48, color: cs.onSurface.withOpacity(0.2)),
                                      const SizedBox(height: 12),
                                      Text(
                                        _searchQuery.isNotEmpty ? 'No notes match your search' : 'No clinical notes recorded yet',
                                        style: GoogleFonts.poppins(color: cs.onSurface.withOpacity(0.45)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                itemBuilder: (context, idx) => _buildNoteCard(filtered[idx], cs),
                              ),
                      ],
                    ),
                  );
                }
              },
            ),
    );
  }

  void _showManageTemplatesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Note Templates', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditTemplateDialog(null, onSaved: () async {
                    await _loadNotesAndSuggestions();
                    setDlgState(() {});
                  }),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: _templates.isEmpty
                  ? const Center(child: Text('No custom templates yet.'))
                  : ListView.builder(
                      itemCount: _templates.length,
                      itemBuilder: (context, index) {
                        final t = _templates[index];
                        final isBuiltIn = t.id.startsWith('__builtin');
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(t.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${t.category} • ${t.isSoap ? "SOAP" : "Text"}', style: GoogleFonts.poppins(fontSize: 11)),
                            trailing: isBuiltIn
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: Text('System', style: GoogleFonts.poppins(fontSize: 10, color: cs.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold)),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        onPressed: () => _showAddEditTemplateDialog(t, onSaved: () async {
                                          await _loadNotesAndSuggestions();
                                          setDlgState(() {});
                                        }),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline_rounded, size: 18, color: cs.error),
                                        onPressed: () async {
                                          await _templateRepository.deleteTemplate(t.id);
                                          await _loadNotesAndSuggestions();
                                          setDlgState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddEditTemplateDialog(NoteTemplate? template, {required VoidCallback onSaved}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: template?.name ?? '');
    final bodyCtrl = TextEditingController(text: template?.body ?? '');
    final subCtrl = TextEditingController(text: template?.soapSubjective ?? '');
    final objCtrl = TextEditingController(text: template?.soapObjective ?? '');
    final assCtrl = TextEditingController(text: template?.soapAssessment ?? '');
    final planCtrl = TextEditingController(text: template?.soapPlan ?? '');
    String category = template?.category ?? 'General';
    bool isSoap = template?.isSoap ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(template == null ? 'Create Template' : 'Edit Template', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Template Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setDlgState(() => category = v ?? category),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text('Use SOAP Structure', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    value: isSoap,
                    onChanged: (val) => setDlgState(() => isSoap = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 10),
                  if (isSoap) ...[
                    TextFormField(
                      controller: subCtrl,
                      decoration: const InputDecoration(labelText: 'Subjective (S)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: objCtrl,
                      decoration: const InputDecoration(labelText: 'Objective (O)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: assCtrl,
                      decoration: const InputDecoration(labelText: 'Assessment (A)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: planCtrl,
                      decoration: const InputDecoration(labelText: 'Plan (P)'),
                      maxLines: 2,
                    ),
                  ] else ...[
                    TextFormField(
                      controller: bodyCtrl,
                      decoration: const InputDecoration(labelText: 'Template Text'),
                      maxLines: 4,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final newTemplate = NoteTemplate(
                  id: template?.id ?? const Uuid().v4(),
                  name: nameCtrl.text.trim(),
                  category: category,
                  body: isSoap ? '' : bodyCtrl.text.trim(),
                  isSoap: isSoap,
                  soapSubjective: isSoap ? subCtrl.text.trim() : '',
                  soapObjective: isSoap ? objCtrl.text.trim() : '',
                  soapAssessment: isSoap ? assCtrl.text.trim() : '',
                  soapPlan: isSoap ? planCtrl.text.trim() : '',
                  createdAt: template?.createdAt ?? DateTime.now(),
                );

                if (template == null) {
                  await _templateRepository.saveTemplate(newTemplate);
                } else {
                  await _templateRepository.updateTemplate(newTemplate);
                }
                onSaved();
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
