import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../services/app_preferences.dart';

class ClinicalNote {
  final String id;
  final String patientName;
  final String note;
  final String category;
  final DateTime createdAt;
  final bool isTodo;
  final bool isCompleted;

  ClinicalNote({
    required this.id,
    required this.patientName,
    required this.note,
    required this.category,
    required this.createdAt,
    this.isTodo = false,
    this.isCompleted = false,
  });

  factory ClinicalNote.fromJson(Map<String, dynamic> json) {
    return ClinicalNote(
      id: json['id']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isTodo: json['isTodo'] == true,
      isCompleted: json['isCompleted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientName': patientName,
      'note': note,
      'category': category,
      'createdAt': createdAt.toIso8601String(),
      'isTodo': isTodo,
      'isCompleted': isCompleted,
    };
  }

  ClinicalNote copyWith({
    String? id,
    String? patientName,
    String? note,
    String? category,
    DateTime? createdAt,
    bool? isTodo,
    bool? isCompleted,
  }) {
    return ClinicalNote(
      id: id ?? this.id,
      patientName: patientName ?? this.patientName,
      note: note ?? this.note,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      isTodo: isTodo ?? this.isTodo,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class ClinicalNotesRepository {
  ClinicalNotesRepository() : _prefsFuture = AppPreferences.instance.prefs;

  final Future<SharedPreferences> _prefsFuture;
  static const String _notesKey = 'clinic_clinical_notes';
  static const Duration _cacheTtl = Duration(seconds: 30);

  static List<ClinicalNote>? _cachedNotes;
  static DateTime? _cachedAt;

  bool get _useFirestore {
    try {
      return Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<ClinicalNote>> loadNotes() async {
    final now = DateTime.now();
    if (_cachedNotes != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return List<ClinicalNote>.unmodifiable(_cachedNotes!);
    }

    if (_useFirestore) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('clinical_notes')
            .get();
        final notes = snapshot.docs
            .map((doc) => ClinicalNote.fromJson({...doc.data(), 'id': doc.id}))
            .toList();
        notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _saveNotes(notes);
        return notes;
      } catch (error) {
        debugPrint('Failed to load notes from Firestore: $error');
      }
    }

    final prefs = await _prefsFuture;
    final raw = prefs.getString(_notesKey);
    if (raw == null || raw.isEmpty) {
      _cachedNotes = const [];
      _cachedAt = now;
      return _cachedNotes!;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final notes = decoded
        .map(
          (entry) =>
              ClinicalNote.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(growable: false);
    _cachedNotes = notes;
    _cachedAt = now;
    return List<ClinicalNote>.unmodifiable(notes);
  }

  Future<void> _saveNotes(List<ClinicalNote> notes) async {
    final prefs = await _prefsFuture;
    final encoded = jsonEncode(notes.map((item) => item.toJson()).toList());
    await prefs.setString(_notesKey, encoded);
    _cachedNotes = List<ClinicalNote>.unmodifiable(notes);
    _cachedAt = DateTime.now();
  }

  Future<void> saveNote(ClinicalNote note) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('clinical_notes')
            .doc(note.id)
            .set(note.toJson());
      } catch (error) {
        debugPrint('Failed to save note to Firestore: $error');
      }
    }
    _cachedNotes = null;
    _cachedAt = null;
    final notes = await loadNotes();
    final next = [note, ...notes];
    await _saveNotes(next);
  }

  Future<void> deleteNote(String id) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('clinical_notes')
            .doc(id)
            .delete();
      } catch (error) {
        debugPrint('Failed to delete note from Firestore: $error');
      }
    }
    _cachedNotes = null;
    _cachedAt = null;
    final notes = await loadNotes();
    final updated = notes.where((n) => n.id != id).toList();
    await _saveNotes(updated);
  }

  Future<void> updateNote(ClinicalNote note) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('clinical_notes')
            .doc(note.id)
            .set(note.toJson());
      } catch (error) {
        debugPrint('Failed to update note in Firestore: $error');
      }
    }
    _cachedNotes = null;
    _cachedAt = null;
    final notes = await loadNotes();
    final updated = notes.map((n) => n.id == note.id ? note : n).toList();
    await _saveNotes(updated);
  }
}
