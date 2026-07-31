import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/appointment.dart';
import '../../services/app_preferences.dart';

class AppointmentRepository {
  AppointmentRepository() : _prefsFuture = AppPreferences.instance.prefs;

  final Future<SharedPreferences> _prefsFuture;
  static const String _appointmentsKey = 'clinic_booked_appointments';
  static const Duration _cacheTtl = Duration(seconds: 30);

  static List<Appointment>? _cachedAppointments;
  static DateTime? _cachedAt;

  bool get _useFirestore {
    try {
      return Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<Appointment>> loadAppointments() async {
    final now = DateTime.now();
    if (_cachedAppointments != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return List<Appointment>.unmodifiable(_cachedAppointments!);
    }

    if (_useFirestore) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('appointments')
            .get()
            .timeout(const Duration(seconds: 3));
        final appointments = snapshot.docs
            .map((doc) => Appointment.fromJson({...doc.data(), 'id': doc.id}))
            .toList();
        // Sort in memory (descending scheduledAt) to avoid index-creation requirements in Firestore
        appointments.sort((a, b) {
          if (a.scheduledAt == null && b.scheduledAt == null) return 0;
          if (a.scheduledAt == null) return 1;
          if (b.scheduledAt == null) return -1;
          return b.scheduledAt!.compareTo(a.scheduledAt!);
        });
        // Persist to SharedPreferences so it's cached locally
        await _saveAppointments(appointments);
        return appointments;
      } catch (error) {
        debugPrint('Failed/Timed out loading appointments from Firestore (using local cache): $error');
      }
    }

    final prefs = await _prefsFuture;
    final raw = prefs.getString(_appointmentsKey);
    if (raw == null || raw.isEmpty) {
      _cachedAppointments = const [];
      _cachedAt = now;
      return _cachedAppointments!;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final appointments = decoded
          .map(
            (entry) =>
                Appointment.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList(growable: false);
      _cachedAppointments = appointments;
      _cachedAt = now;
      return List<Appointment>.unmodifiable(appointments);
    } catch (e) {
      debugPrint('Error parsing cached appointments: $e');
      return const [];
    }
  }

  Future<void> _saveAppointments(List<Appointment> appointments) async {
    final prefs = await _prefsFuture;
    final encoded = jsonEncode(
      appointments.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_appointmentsKey, encoded);
    _cachedAppointments = List<Appointment>.unmodifiable(appointments);
    _cachedAt = DateTime.now();
  }

  Future<bool> saveAppointment(Appointment appointment) async {
    // 1. Immediately persist locally to SharedPreferences for instant offline availability
    final currentList = await loadAppointments();
    final filtered = currentList.where((a) => a.id != appointment.id).toList();
    final nextList = [appointment, ...filtered];
    await _saveAppointments(nextList);

    // 2. Sync to Firestore with 3-second timeout
    bool remoteSuccess = true;
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(appointment.id)
            .set(appointment.toJson())
            .timeout(const Duration(seconds: 3));
      } catch (error) {
        debugPrint('Firestore save error or timeout (proceeding offline): $error');
        remoteSuccess = false;
      }
    }
    return remoteSuccess;
  }

  Future<Appointment?> findById(String id) async {
    final appointments = await loadAppointments();
    for (final appointment in appointments) {
      if (appointment.id == id) {
        return appointment;
      }
    }

    if (_useFirestore) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(id)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          return Appointment.fromJson({...doc.data()!, 'id': doc.id});
        }
      } catch (error) {
        debugPrint('Failed to find appointment by id in Firestore: $error');
      }
    }
    return null;
  }

  Future<void> updateAppointment(Appointment updatedAppointment) async {
    // 1. Update local SharedPreferences first
    final currentList = await loadAppointments();
    final nextList = currentList
        .map((item) => item.id == updatedAppointment.id ? updatedAppointment : item)
        .toList();
    await _saveAppointments(nextList);

    // 2. Sync to Firestore in background / non-blocking with 3-second timeout
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(updatedAppointment.id)
            .set(updatedAppointment.toJson())
            .timeout(const Duration(seconds: 3));
      } catch (error) {
        debugPrint('Firestore update offline queued / timed out: $error');
      }
    }
  }

  Future<void> deleteAppointment(String appointmentId) async {
    // 1. Delete from local SharedPreferences first
    final currentList = await loadAppointments();
    final nextList = currentList
        .where((item) => item.id != appointmentId)
        .toList();
    await _saveAppointments(nextList);

    // 2. Sync to Firestore in background / non-blocking with 3-second timeout
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(appointmentId)
            .delete()
            .timeout(const Duration(seconds: 3));
      } catch (error) {
        debugPrint('Firestore delete offline queued / timed out: $error');
      }
    }
  }
}
