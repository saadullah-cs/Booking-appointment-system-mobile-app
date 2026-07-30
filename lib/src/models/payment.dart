class Payment {
  final String id;
  final String patientName;
  final double amount; // Represents the total bill amount
  final double paidAmount; // Represents the amount paid so far
  final DateTime paidAt;
  final String method;
  final String status;
  final String note;
  final DateTime?
  reminderDate; // Date to remind for collecting outstanding balance

  Payment({
    required this.id,
    required this.patientName,
    required this.amount,
    required this.paidAmount,
    required this.paidAt,
    required this.method,
    required this.status,
    this.note = '',
    this.reminderDate,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    final double total = (json['amount'] as num?)?.toDouble() ?? 0;
    final double paid =
        (json['paidAmount'] as num?)?.toDouble() ??
        ((json['status']?.toString().toLowerCase() == 'paid') ? total : 0.0);
    return Payment(
      id: json['id']?.toString() ?? '',
      patientName: json['patientName']?.toString() ?? '',
      amount: total,
      paidAmount: paid,
      paidAt:
          DateTime.tryParse(json['paidAt']?.toString() ?? '') ?? DateTime.now(),
      method: json['method']?.toString() ?? 'Cash',
      status: json['status']?.toString() ?? 'Paid',
      note: json['note']?.toString() ?? '',
      reminderDate: json['reminderDate'] != null
          ? DateTime.tryParse(json['reminderDate'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientName': patientName,
      'amount': amount,
      'paidAmount': paidAmount,
      'paidAt': paidAt.toIso8601String(),
      'method': method,
      'status': status,
      'note': note,
      'reminderDate': reminderDate?.toIso8601String(),
    };
  }
}
