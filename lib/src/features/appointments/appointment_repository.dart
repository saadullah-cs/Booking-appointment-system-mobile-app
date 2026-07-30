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
            .get();
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
        debugPrint('Failed to load appointments from Firestore: $error');
      }
    }

    final prefs = await _prefsFuture;
    final raw = prefs.getString(_appointmentsKey);
    if (raw == null || raw.isEmpty) {
      _cachedAppointments = const [];
      _cachedAt = now;
      return _cachedAppointments!;
    }

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
    bool remoteSuccess = true;
    if (_useFirestore) {
      try {
        // Wrap with 3s timeout for offline optimism
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(appointment.id)
            .set(appointment.toJson())
            .timeout(const Duration(seconds: 3));
      } catch (error) {
        debugPrint(
          'Firestore save error or timeout (proceeding offline): $error',
        );
        remoteSuccess = false;
        // We catch the error so the local cache still updates
      }
    }
    // Invalidate the cache to ensure we reload fresh list
    _cachedAppointments = null;
    _cachedAt = null;
    final appointments = await loadAppointments();
    // Prevent duplicates in local list if already loaded/updated
    final filtered = appointments.where((a) => a.id != appointment.id).toList();
    final next = [appointment, ...filtered];
    await _saveAppointments(next);
    return remoteSuccess;
  }

  Future<Appointment?> findById(String id) async {
    if (_useFirestore) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('appointments')
            .doc(id)
            .get();
        if (doc.exists && doc.data() != null) {
          return Appointment.fromJson({...doc.data()!, 'id': doc.id});
        }
      } catch (error) {
        debugPrint('Failed to find appointment by id in Firestore: $error');
      }
    }
    final appointments = await loadAppointments();
    for (final appointment in appointments) {
      if (appointment.id == id) {
        return appointment;
      }
    }
    return null;
  }

  Future<void> updateAppointment(Appointment updatedAppointment) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(updatedAppointment.id)
            .set(updatedAppointment.toJson());
      } catch (error) {
        debugPrint('Failed to update appointment in Firestore: $error');
      }
    }
    // Invalidate the cache
    _cachedAppointments = null;
    _cachedAt = null;
    final appointments = await loadAppointments();
    final next = appointments
        .map(
          (item) =>
              item.id == updatedAppointment.id ? updatedAppointment : item,
        )
        .toList(growable: false);
    await _saveAppointments(next);
  }

  Future<void> deleteAppointment(String appointmentId) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(appointmentId)
            .delete();
      } catch (error) {
        debugPrint('Failed to delete appointment in Firestore: $error');
      }
    }
    // Invalidate the cache
    _cachedAppointments = null;
    _cachedAt = null;
    final appointments = await loadAppointments();
    final next = appointments
        .where((item) => item.id != appointmentId)
        .toList(growable: false);
    await _saveAppointments(next);
  }
}
