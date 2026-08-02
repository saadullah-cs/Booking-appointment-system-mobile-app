import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/appointments/appointment_repository.dart';
import '../features/payments/payment_repository.dart';
import '../features/notes/clinical_notes_repository.dart';
import '../features/notes/note_template_repository.dart';
import '../models/appointment.dart';
import 'payment_gateway_service.dart';

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository();
});

final appointmentsProvider =
    StateNotifierProvider<AppointmentsNotifier, List<Appointment>>((ref) {
      return AppointmentsNotifier(ref.watch(appointmentRepositoryProvider));
    });

class AppointmentsNotifier extends StateNotifier<List<Appointment>> {
  AppointmentsNotifier(this._repository) : super([]) {
    load();
  }

  final AppointmentRepository _repository;

  Future<void> load() async {
    final list = await _repository.loadAppointments();
    state = list;
  }

  Future<bool> save(Appointment appointment) async {
    final success = await _repository.saveAppointment(appointment);
    await load();
    return success;
  }

  Future<void> update(Appointment appointment) async {
    await _repository.updateAppointment(appointment);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.deleteAppointment(id);
    await load();
  }
}

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
