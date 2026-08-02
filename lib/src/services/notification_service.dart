import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../routes/app_router.dart';
import 'package:intl/intl.dart';
import '../models/appointment.dart';
import '../models/payment.dart';
import '../features/appointments/appointment_repository.dart';
import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  final data = message.data;
  final notification = message.notification;
  String? title = notification?.title;
  String? body = notification?.body;

  if (title == null || body == null) {
    title = data['title'] ?? data['notification_title'] ?? 'GCT Clinic Alert';
    body =
        data['body'] ?? data['notification_body'] ?? 'You have a new update.';
  }

  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  final iosInit = DarwinInitializationSettings();
  final initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );
  await localNotifications.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'gct_channel_01',
    'GCT Notifications',
    channelDescription: 'General notifications for GCT app',
    importance: Importance.max,
    priority: Priority.high,
  );
  const iosDetails = DarwinNotificationDetails();
  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  String? payload;
  final appointmentId = data['appointmentId'] ?? data['appointment_id'];
  if (appointmentId != null && appointmentId.toString().isNotEmpty) {
    payload = '/appointment/${appointmentId.toString()}';
  } else {
    final screen = data['screen']?.toString().toLowerCase();
    if (screen != null) {
      payload = '/$screen';
    }
  }

  await localNotifications.show(0, title, body, details, payload: payload);

  final bodyText = body ?? '';

  if (bodyText.toLowerCase().contains('appointment') ||
      bodyText.toLowerCase().contains('reminder')) {
    try {
      final tts = FlutterTts();
      await tts.setLanguage("en-US");
      await tts.setSpeechRate(0.55);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      await tts.speak(bodyText);
    } catch (_) {}
  }
}

class NotificationService {
  NotificationService._private();
  static final NotificationService _instance = NotificationService._private();
  factory NotificationService() => _instance;

  FirebaseMessaging? _fcm;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();
  bool _isOfflineBookingPending = false;

  void setOfflineBookingPending(bool pending) {
    _isOfflineBookingPending = pending;
  }

  Future<void> init() async {
    try {
      tz.initializeTimeZones();
      _initConnectivityListener();
      try {
        await _tts.setLanguage("en-US");
        await _tts.setSpeechRate(0.55);
        await _tts.setVolume(1.0);
        await _tts.setPitch(1.0);
      } catch (e) {
        if (kDebugMode) print('TTS initialization failed: $e');
      }
      // Configure Firebase Messaging only if Firebase is initialized.
      try {
        if (Firebase.apps.isNotEmpty) {
          _fcm = FirebaseMessaging.instance;
          // Configure background handler
          FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

          // Request permissions (iOS/macOS)
          await _fcm!.requestPermission(alert: true, badge: true, sound: true);
        } else {
          if (kDebugMode) {
            debugPrint('Firebase not initialized; skipping FCM setup.');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('FCM setup skipped or failed: $e');
      }

      // Initialize local notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      final iosInit = DarwinInitializationSettings();
      final initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: null,
      );

      await _local.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationResponse(response);
        },
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final androidImplementation = _local
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

          await androidImplementation?.requestNotificationsPermission();
          await androidImplementation?.requestExactAlarmsPermission();
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'Failed to request Android notification permissions: $e',
            );
          }
        }
      }

      // Foreground message handler to display local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        try {
          final notification = msg.notification;
          if (notification != null) {
            showLocalNotification(
              notification.title ?? '',
              notification.body ?? '',
              payload: _routeFromMessage(msg),
            );
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error showing local notification: $e');
        }
      });

      // Optionally handle messages opened from terminated/background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
        _navigateToRoute(_routeFromMessage(msg));
      });

      // Handle message that opened the app when terminated (FCM)
      final initialMessage = await _fcm?.getInitialMessage();
      if (initialMessage != null) {
        _navigateToRoute(_routeFromMessage(initialMessage));
      }

      // Handle message that opened the app when terminated (Local Notification)
      final launchDetails = await _local.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payload = launchDetails.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          _navigateToRoute(payload);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Notification initialization failed: $e');
    }
  }

  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> _speakAppointmentDetails(String appointmentId) async {
    try {
      final repo = AppointmentRepository();
      final appointments = await repo.loadAppointments();
      final apt = appointments.firstWhere((a) => a.id == appointmentId);
      final String formattedTime;
      final String formattedDayDate;
      if (apt.scheduledAt != null) {
        formattedTime = DateFormat(
          'hh:mm a',
        ).format(apt.scheduledAt!.toLocal());
        formattedDayDate = DateFormat(
          'EEEE, MMMM d',
        ).format(apt.scheduledAt!.toLocal());
      } else {
        formattedTime = apt.time;
        formattedDayDate = 'scheduled time';
      }
      final textToSpeak =
          'Reminder. Appointment with ${apt.patientName} is scheduled on $formattedDayDate at $formattedTime.';
      await speak(textToSpeak);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to speak appointment details: $e');
    }
  }

  Future<void> showLocalNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'gct_channel_01',
      'GCT Notifications',
      channelDescription: 'General notifications for GCT app',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
    );
    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _local.show(0, title, body, details, payload: payload);

    if (body.toLowerCase().contains('appointment') ||
        body.toLowerCase().contains('reminder')) {
      await speak(body);
    }
  }

  /// Shows a local notification for a new chat message.
  Future<void> showChatNotification({
    required String senderName,
    required String message,
    required bool isStaff,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'gct_chat_channel',
        'GCT Chat',
        channelDescription:
            'New message notifications for the clinic group chat',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final title = isStaff
          ? '💬 Staff: $senderName'
          : '💬 Doctor: $senderName';
      final body = message.length > 80
          ? '${message.substring(0, 80)}…'
          : message;

      await _local.show(
        99, // fixed ID so repeated messages replace each other
        title,
        body,
        details,
        payload: '/chat',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('showChatNotification failed: $e');
    }
  }

  Future<String?> getDeviceToken() async {
    try {
      return await _fcm?.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get FCM token: $e');
      return null;
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _navigateToRoute(payload);
    }
  }

  String _routeFromMessage(RemoteMessage message) {
    final data = message.data;
    final appointmentId = data['appointmentId'] ?? data['appointment_id'];
    if (appointmentId != null && appointmentId.toString().isNotEmpty) {
      return '/appointment/${appointmentId.toString()}';
    }
    final screen = data['screen']?.toString().toLowerCase();
    if (screen == 'chat') return '/chat';
    if (screen == 'profile') return '/profile';
    if (screen == 'appointments') return '/appointments';
    if (screen == 'dashboard') return '/dashboard';
    return '/dashboard';
  }

  void _navigateToRoute(String route) {
    _performNavigation(route);
    if (route.startsWith('/appointment/')) {
      final appointmentId = route.substring('/appointment/'.length);
      _speakAppointmentDetails(appointmentId);
    }
  }

  Future<void> _performNavigation(String route) async {
    int attempts = 0;
    // Wait until navigator context is loaded and ready
    while (appNavigatorKey.currentContext == null && attempts < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    final context = appNavigatorKey.currentContext;
    if (context == null) {
      if (kDebugMode) {
        print('Unable to navigate: app context is not ready yet.');
      }
      return;
    }

    try {
      GoRouter.of(context).go(route);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to navigate to route "$route": $e');
    }
  }

  static int getNoteReminderId(String id) =>
      (id.hashCode.abs() % 50000000) + 200000000;

  Future<void> scheduleNoteReminder({
    required String noteId,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final reminderId = getNoteReminderId(noteId);
    await cancelNotification(reminderId);
    await scheduleLocalNotification(
      id: reminderId,
      title: '📌 Clinical Note Reminder: $title',
      body: body,
      scheduledDate: scheduledDate,
      payload: '/notes',
    );
  }

  static int getReminderId(String id) => (id.hashCode.abs() % 50000000) * 2;
  static int getStartId(String id) => ((id.hashCode.abs() % 50000000) * 2) + 1;
  static int getPaymentReminderId(String id) =>
      (id.hashCode.abs() % 50000000) + 100000000;

  Future<void> testZonedNotification(int delaySeconds) async {
    final scheduledDate = DateTime.now().add(Duration(seconds: delaySeconds));
    await scheduleLocalNotification(
      id: 9999,
      title: 'Background Test 🧪',
      body: 'This notification was scheduled for $delaySeconds seconds delay.',
      scheduledDate: scheduledDate,
      payload: '/dashboard',
    );
    if (kDebugMode) {
      debugPrint(
        'Test notification scheduled for $delaySeconds seconds from now.',
      );
    }
  }

  Future<void> scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (scheduledDate.isBefore(DateTime.now())) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'gct_scheduled_channel_v3',
      'GCT Scheduled Reminders',
      channelDescription: 'Scheduled reminders for GCT app',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use tz.local instead of UTC for accurate local scheduling
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    try {
      await _local.zonedSchedule(
        id,
        title,
        body,
        tzScheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Exact schedule failed (falling back to inexact): $e');
      }
      try {
        await _local.zonedSchedule(
          id,
          title,
          body,
          tzScheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      } catch (ex) {
        if (kDebugMode) {
          debugPrint('Inexact schedule failed: $ex');
        }
      }
    }
  }

  Future<void> scheduleAppointmentReminders(Appointment apt) async {
    final now = DateTime.now();
    final reminderId = getReminderId(apt.id);
    final startId = getStartId(apt.id);

    await cancelNotification(reminderId);
    await cancelNotification(startId);

    if (apt.scheduledAt != null && apt.scheduledAt!.isAfter(now)) {
      final statusLower = apt.status.toLowerCase();
      if (statusLower == 'confirmed' || statusLower == 'pending') {
        final reminderTime = apt.scheduledAt!.subtract(
          const Duration(hours: 1),
        );
        final formattedTime = DateFormat(
          'hh:mm a',
        ).format(apt.scheduledAt!.toLocal());

        if (reminderTime.isAfter(now)) {
          await scheduleLocalNotification(
            id: reminderId,
            title: 'Upcoming Appointment Reminder ⏰',
            body:
                'Upcoming Appointment in 1 Hour: ${apt.patientName} at $formattedTime.',
            scheduledDate: reminderTime,
            payload: '/appointment/${apt.id}',
          );
        }

        await scheduleLocalNotification(
          id: startId,
          title: 'Appointment Starting Now! 📅',
          body:
              'Your appointment with ${apt.patientName} is starting now ($formattedTime).',
          scheduledDate: apt.scheduledAt!,
          payload: '/appointment/${apt.id}',
        );
      }
    }
  }

  Future<void> syncScheduledNotifications(
    List<Appointment> appointments,
  ) async {
    for (final apt in appointments) {
      await scheduleAppointmentReminders(apt);
    }
  }

  Future<void> syncPaymentReminders(List<Payment> payments) async {
    final now = DateTime.now();
    for (final payment in payments) {
      final reminderId = getPaymentReminderId(payment.id);
      await cancelNotification(reminderId);

      if (payment.reminderDate != null && payment.reminderDate!.isAfter(now)) {
        final balance = payment.amount - payment.paidAmount;
        if (balance > 0) {
          await scheduleLocalNotification(
            id: reminderId,
            title: 'Payment Reminder 💳',
            body:
                'Payment reminder: Balance of Rs. ${balance.toStringAsFixed(0)} for ${payment.patientName} is due.',
            scheduledDate: payment.reminderDate!,
            payload: '/dashboard',
          );
        }
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _local.cancel(id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_title_$id');
      await prefs.remove('alarm_body_$id');
      await prefs.remove('alarm_payload_$id');
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to cancel notification $id: $e');
    }
  }

  Future<void> cancelAppointmentNotifications(String appointmentId) async {
    await cancelNotification(getReminderId(appointmentId));
    await cancelNotification(getStartId(appointmentId));
  }

  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      if (result.any((r) => r != ConnectivityResult.none) &&
          _isOfflineBookingPending) {
        _isOfflineBookingPending = false;

        showLocalNotification(
          'Internet Restored! 🌐',
          'Your internet is restored and your appointment is officially confirmed!',
        );

        final context = appNavigatorKey.currentContext;
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your internet is restored and your appointment is officially confirmed!',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }
}
