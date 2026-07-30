import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/appointments/appointment_repository.dart';
import '../features/appointments/booking_screen.dart';
import '../features/appointments/appointments_list_screen.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/calculator/calculator_screen.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/notes/clinical_notes_screen.dart';
import '../features/patient/profile_screen.dart';
import '../features/patient/patient_history_screen.dart';
import '../features/payments/payment_screen.dart';
import '../features/appointments/appointment_detail_screen.dart';

import '../features/auth/screens/splash_entry_screen.dart';
import '../features/auth/screens/security_settings_screen.dart';
import '../features/auth/screens/security_lock_screen.dart';
import '../features/auth/screens/staff_lock_screen.dart';
import '../features/auth/screens/staff_management_screen.dart';
import '../features/auth/screens/staff_login_screen.dart';
import '../features/dashboard/staff_dashboard_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/vision_analyzer/vision_analyzer_screen.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/',
    routes: <GoRoute>[
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashEntryScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const PatientProfileScreen(),
      ),
      GoRoute(
        path: '/patient-history',
        name: 'patientHistory',
        builder: (context, state) {
          final name = state.queryParameters['name'] ?? '';
          final phone = state.queryParameters['phone'] ?? '';
          return PatientHistoryScreen(patientName: name, phoneNumber: phone);
        },
      ),
      GoRoute(
        path: '/booking',
        name: 'booking',
        builder: (context, state) {
          final initialData = state.extra as Map<String, dynamic>?;
          return BookingScreen(initialData: initialData);
        },
      ),
      GoRoute(
        path: '/appointments',
        name: 'appointments',
        builder: (context, state) => const AppointmentsListScreen(),
      ),
      GoRoute(
        path: '/analytics',
        name: 'analytics',
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: '/payments',
        name: 'payments',
        builder: (context, state) => const PaymentScreen(),
      ),
      GoRoute(
        path: '/calculator',
        name: 'calculator',
        builder: (context, state) => const CalculatorScreen(),
      ),
      GoRoute(
        path: '/notes',
        name: 'notes',
        builder: (context, state) => const ClinicalNotesScreen(),
      ),

      GoRoute(
        path: '/security-settings',
        name: 'securitySettings',
        builder: (context, state) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: '/security-lock',
        name: 'securityLock',
        builder: (context, state) => const SecurityLockScreen(),
      ),
      GoRoute(
        path: '/staff-lock',
        name: 'staffLock',
        builder: (context, state) => const StaffLockScreen(),
      ),
      GoRoute(
        path: '/staff-management',
        name: 'staffManagement',
        builder: (context, state) => const StaffManagementScreen(),
      ),
      GoRoute(
        path: '/staff-login',
        name: 'staffLogin',
        builder: (context, state) => const StaffLoginScreen(),
      ),
      GoRoute(
        path: '/staff-dashboard',
        name: 'staffDashboard',
        builder: (context, state) => const StaffDashboardScreen(),
      ),
      GoRoute(
        path: '/chat',
        name: 'chat',
        builder: (context, state) => const ChatScreen(),
      ),
      GoRoute(
        path: '/vision-analyzer',
        name: 'visionAnalyzer',
        builder: (context, state) => const VisionAnalyzerScreen(),
      ),
      GoRoute(
        path: '/appointment/:id',
        name: 'appointmentDetail',
        builder: (context, state) =>
            AppointmentDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/payment-callback',
        name: 'paymentCallback',
        builder: (context, state) {
          final status = state.queryParameters['status'] ?? '';
          final appointmentId = state.queryParameters['id'] ?? '';

          if (status == 'success' && appointmentId.isNotEmpty) {
            // Trigger background update
            Future.microtask(() async {
              final repo = AppointmentRepository();
              final apt = await repo.findById(appointmentId);
              if (apt != null) {
                await repo.updateAppointment(
                  apt.copyWith(paymentStatus: 'paid'),
                );
              }
            });
          }

          return const DashboardScreen();
        },
      ),
    ],
  );
});
