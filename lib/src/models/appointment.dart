class Appointment {
  final String id;
  final String patientName;
  final String time;
  final String treatmentType;
  final String status;
  final DateTime? scheduledAt;
  final String phoneNumber;
  final String email;
  final String visitReason;
  final String patientNote;
  final String cancellationReason;
  final DateTime? updatedAt;
  final bool isEmergency;
  final String patientProfession;

  // New Clinical Report Fields
  final int? painLevel;
  final String bloodPressure;
  final int? pulseRate;
  final String adjustedSegments;
  final String prescribedExercises;
  final String nextFollowUp;

  // Treatment Plan Fields
  final int? treatmentPlanTotalSessions;
  final int? sessionNumber;

  // Appointment Duration
  final int durationMinutes;

  // New Fields
  final DateTime? dateOfBirth;
  final String adjustmentTechnique;
  final String patientImprovement;
  final String posturalPhotoPath;

  // Payment Tracking
  final String paymentMethod; // 'online' | 'cash'
  final String paymentStatus; // 'paid' | 'pending'
  final double amount;

  Appointment({
    required this.id,
    required this.patientName,
    required this.time,
    required this.treatmentType,
    required this.status,
    this.scheduledAt,
    this.phoneNumber = '',
    this.email = '',
    this.visitReason = '',
    this.patientNote = '',
    this.cancellationReason = '',
    this.updatedAt,
    this.isEmergency = false,
    this.patientProfession = '',
    this.painLevel,
    this.bloodPressure = '',
    this.pulseRate,
    this.adjustedSegments = '',
    this.prescribedExercises = '',
    this.nextFollowUp = '',
    this.treatmentPlanTotalSessions,
    this.sessionNumber,
    this.durationMinutes = 40,
    this.dateOfBirth,
    this.adjustmentTechnique = '',
    this.patientImprovement = '',
    this.posturalPhotoPath = '',
    this.paymentMethod = 'cash',
    this.paymentStatus = 'pending',
    this.amount = 0.0,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      treatmentType: json['treatmentType']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
      scheduledAt: DateTime.tryParse(json['scheduledAt']?.toString() ?? ''),
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      visitReason: json['visitReason']?.toString() ?? '',
      patientNote: json['patientNote']?.toString() ?? '',
      cancellationReason: json['cancellationReason']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      isEmergency: json['isEmergency'] == true || json['isEmergency'] == 'true',
      patientProfession: json['patientProfession']?.toString() ?? '',
      painLevel: json['painLevel'] != null
          ? int.tryParse(json['painLevel'].toString())
          : null,
      bloodPressure: json['bloodPressure']?.toString() ?? '',
      pulseRate: json['pulseRate'] != null
          ? int.tryParse(json['pulseRate'].toString())
          : null,
      adjustedSegments: json['adjustedSegments']?.toString() ?? '',
      prescribedExercises: json['prescribedExercises']?.toString() ?? '',
      nextFollowUp: json['nextFollowUp']?.toString() ?? '',
      treatmentPlanTotalSessions: json['treatmentPlanTotalSessions'] != null
          ? int.tryParse(json['treatmentPlanTotalSessions'].toString())
          : null,
      sessionNumber: json['sessionNumber'] != null
          ? int.tryParse(json['sessionNumber'].toString())
          : null,
      durationMinutes: json['durationMinutes'] != null
          ? int.tryParse(json['durationMinutes'].toString()) ?? 40
          : 40,
      dateOfBirth: DateTime.tryParse(json['dateOfBirth']?.toString() ?? ''),
      adjustmentTechnique: json['adjustmentTechnique']?.toString() ?? '',
      patientImprovement: json['patientImprovement']?.toString() ?? '',
      posturalPhotoPath: json['posturalPhotoPath']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
      paymentStatus: json['paymentStatus']?.toString() ?? 'pending',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientName': patientName,
      'time': time,
      'treatmentType': treatmentType,
      'status': status,
      'scheduledAt': scheduledAt?.toIso8601String(),
      'phoneNumber': phoneNumber,
      'email': email,
      'visitReason': visitReason,
      'patientNote': patientNote,
      'cancellationReason': cancellationReason,
      'updatedAt': updatedAt?.toIso8601String(),
      'isEmergency': isEmergency,
      'patientProfession': patientProfession,
      'painLevel': painLevel,
      'bloodPressure': bloodPressure,
      'pulseRate': pulseRate,
      'adjustedSegments': adjustedSegments,
      'prescribedExercises': prescribedExercises,
      'nextFollowUp': nextFollowUp,
      'treatmentPlanTotalSessions': treatmentPlanTotalSessions,
      'sessionNumber': sessionNumber,
      'durationMinutes': durationMinutes,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'adjustmentTechnique': adjustmentTechnique,
      'patientImprovement': patientImprovement,
      'posturalPhotoPath': posturalPhotoPath,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'amount': amount,
    };
  }

  Appointment copyWith({
    String? patientName,
    String? time,
    String? treatmentType,
    String? status,
    DateTime? scheduledAt,
    String? phoneNumber,
    String? email,
    String? visitReason,
    String? patientNote,
    String? cancellationReason,
    DateTime? updatedAt,
    bool? isEmergency,
    String? patientProfession,
    int? painLevel,
    String? bloodPressure,
    int? pulseRate,
    String? adjustedSegments,
    String? prescribedExercises,
    String? nextFollowUp,
    int? treatmentPlanTotalSessions,
    int? sessionNumber,
    int? durationMinutes,
    DateTime? dateOfBirth,
    String? adjustmentTechnique,
    String? patientImprovement,
    String? posturalPhotoPath,
    String? paymentMethod,
    String? paymentStatus,
    double? amount,
  }) {
    return Appointment(
      id: id,
      patientName: patientName ?? this.patientName,
      time: time ?? this.time,
      treatmentType: treatmentType ?? this.treatmentType,
      status: status ?? this.status,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      visitReason: visitReason ?? this.visitReason,
      patientNote: patientNote ?? this.patientNote,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      updatedAt: updatedAt ?? this.updatedAt,
      isEmergency: isEmergency ?? this.isEmergency,
      patientProfession: patientProfession ?? this.patientProfession,
      painLevel: painLevel ?? this.painLevel,
      bloodPressure: bloodPressure ?? this.bloodPressure,
      pulseRate: pulseRate ?? this.pulseRate,
      adjustedSegments: adjustedSegments ?? this.adjustedSegments,
      prescribedExercises: prescribedExercises ?? this.prescribedExercises,
      nextFollowUp: nextFollowUp ?? this.nextFollowUp,
      treatmentPlanTotalSessions:
          treatmentPlanTotalSessions ?? this.treatmentPlanTotalSessions,
      sessionNumber: sessionNumber ?? this.sessionNumber,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      adjustmentTechnique: adjustmentTechnique ?? this.adjustmentTechnique,
      patientImprovement: patientImprovement ?? this.patientImprovement,
      posturalPhotoPath: posturalPhotoPath ?? this.posturalPhotoPath,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      amount: amount ?? this.amount,
    );
  }
}
