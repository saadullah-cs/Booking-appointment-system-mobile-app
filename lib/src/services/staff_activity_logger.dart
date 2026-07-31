import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class StaffActivityLog {
  final String id;
  final String staffEmail;
  final String action;
  final String featureUsed;
  final DateTime timestamp;
  final int? sessionDurationMinutes;
  final String? staffPin;

  StaffActivityLog({
    required this.id,
    required this.staffEmail,
    required this.action,
    required this.featureUsed,
    required this.timestamp,
    this.sessionDurationMinutes,
    this.staffPin,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'staffEmail': staffEmail,
        'action': action,
        'featureUsed': featureUsed,
        'timestamp': timestamp.toIso8601String(),
        'sessionDurationMinutes': sessionDurationMinutes,
        'staffPin': staffPin,
      };

  factory StaffActivityLog.fromJson(Map<String, dynamic> json) => StaffActivityLog(
        id: json['id'] as String? ?? '',
        staffEmail: json['staffEmail'] as String? ?? 'Staff Member',
        action: json['action'] as String? ?? 'Activity',
        featureUsed: json['featureUsed'] as String? ?? 'Dashboard',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        sessionDurationMinutes: json['sessionDurationMinutes'] as int?,
        staffPin: json['staffPin'] as String?,
      );
}

class StaffActivityLogger {
  static final StaffActivityLogger _instance = StaffActivityLogger._internal();
  factory StaffActivityLogger() => _instance;
  StaffActivityLogger._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> logActivity({
    required String staffEmail,
    required String action,
    required String featureUsed,
    int? sessionDurationMinutes,
    String? staffPin,
  }) async {
    final logId = DateTime.now().millisecondsSinceEpoch.toString();
    final log = StaffActivityLog(
      id: logId,
      staffEmail: staffEmail,
      action: action,
      featureUsed: featureUsed,
      timestamp: DateTime.now(),
      sessionDurationMinutes: sessionDurationMinutes,
      staffPin: staffPin,
    );

    try {
      await _firestore.collection('staff_activity_logs').doc(logId).set(log.toJson());
    } catch (e) {
      debugPrint('Firestore staff log write error: $e');
    }
  }

  Stream<List<StaffActivityLog>> streamLogs() {
    return _firestore
        .collection('staff_activity_logs')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => StaffActivityLog.fromJson(doc.data())).toList());
  }

  Future<void> clearAllLogs() async {
    try {
      final snap = await _firestore.collection('staff_activity_logs').get();
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Firestore clear staff logs error: $e');
    }
  }
}
