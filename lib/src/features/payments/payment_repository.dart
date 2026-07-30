import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/payment.dart';
import '../../services/app_preferences.dart';

class PaymentRepository {
  PaymentRepository() : _prefsFuture = AppPreferences.instance.prefs;

  final Future<SharedPreferences> _prefsFuture;
  static const String _paymentsKey = 'clinic_patient_payments';
  static const Duration _cacheTtl = Duration(seconds: 30);

  static List<Payment>? _cachedPayments;
  static DateTime? _cachedAt;

  bool get _useFirestore {
    try {
      return Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<Payment>> loadPayments() async {
    final now = DateTime.now();
    if (_cachedPayments != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return List<Payment>.unmodifiable(_cachedPayments!);
    }

    if (_useFirestore) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('payments')
            .get();
        final payments = snapshot.docs
            .map((doc) => Payment.fromJson({...doc.data(), 'id': doc.id}))
            .toList();
        payments.sort((a, b) => b.paidAt.compareTo(a.paidAt));
        await _savePayments(payments);
        return payments;
      } catch (error) {
        debugPrint('Failed to load payments from Firestore: $error');
      }
    }

    final prefs = await _prefsFuture;
    final raw = prefs.getString(_paymentsKey);
    if (raw == null || raw.isEmpty) {
      _cachedPayments = const [];
      _cachedAt = now;
      return _cachedPayments!;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final payments = decoded
        .map(
          (entry) => Payment.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(growable: false);
    _cachedPayments = payments;
    _cachedAt = now;
    return List<Payment>.unmodifiable(payments);
  }

  Future<void> _savePayments(List<Payment> payments) async {
    final prefs = await _prefsFuture;
    final encoded = jsonEncode(payments.map((item) => item.toJson()).toList());
    await prefs.setString(_paymentsKey, encoded);
    _cachedPayments = List<Payment>.unmodifiable(payments);
    _cachedAt = DateTime.now();
  }

  Future<void> savePayment(Payment payment) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('payments')
            .doc(payment.id)
            .set(payment.toJson());
      } catch (error) {
        debugPrint('Failed to save payment to Firestore: $error');
      }
    }
    _cachedPayments = null;
    _cachedAt = null;
    final payments = await loadPayments();
    final index = payments.indexWhere((p) => p.id == payment.id);
    final List<Payment> updated;
    if (index >= 0) {
      updated = List<Payment>.from(payments);
      updated[index] = payment;
    } else {
      updated = [payment, ...payments];
    }
    await _savePayments(updated);
  }

  Future<void> deletePayment(String id) async {
    if (_useFirestore) {
      try {
        await FirebaseFirestore.instance
            .collection('payments')
            .doc(id)
            .delete();
      } catch (error) {
        debugPrint('Failed to delete payment from Firestore: $error');
      }
    }
    _cachedPayments = null;
    _cachedAt = null;
    final payments = await loadPayments();
    final updated = payments.where((p) => p.id != id).toList();
    await _savePayments(updated);
  }

  Future<SharedPreferences> getPrefs() async => _prefsFuture;
}
