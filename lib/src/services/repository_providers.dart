import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/appointments/appointment_repository.dart';
import '../features/payments/payment_repository.dart';
import '../features/notes/clinical_notes_repository.dart';
import '../features/notes/note_template_repository.dart';
import 'payment_gateway_service.dart';

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository();
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository();
});

final paymentGatewayServiceProvider = Provider<PaymentGatewayService>((ref) {
  return PaymentGatewayService();
});

final clinicalNotesRepositoryProvider = Provider<ClinicalNotesRepository>((
  ref,
) {
  return ClinicalNotesRepository();
});

final noteTemplateRepositoryProvider = Provider<NoteTemplateRepository>((ref) {
  return NoteTemplateRepository();
});
