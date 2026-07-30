# Implementation Plan - Background & Offline Notifications

This plan details the implementation of robust background push notifications (FCM) and local offline reminders (1-hour pre-appointment) using `firebase_messaging` and `flutter_local_notifications`.

## User Review Required

> [!IMPORTANT]
> Background message handling requires the handler to be a top-level function. I will ensure `_firebaseBackgroundHandler` is correctly configured and initialized with Firebase options.
> Local reminders will be adjusted to trigger **1 hour** before appointments as requested, utilizing `AndroidAlarmManager` for offline reliability.

## Proposed Changes

### [Notification Service]

#### [MODIFY] [notification_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/notification_service.dart)
- Update `_firebaseBackgroundHandler` to use `DefaultFirebaseOptions` during initialization.
- Modify `scheduleAppointmentReminders` to schedule a reminder **1 hour** before the appointment.
- Ensure `_alarmCallback` handles background state correctly.
- Add `// REMOVE:` comments for instructional steps.

### [Main Entry Point]

#### [MODIFY] [main.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/main.dart)
- Ensure Firebase is initialized correctly for the main app.
- (Optional) Register the background handler here if needed, though `NotificationService.init` currently handles it.

### [Bootstrap Service]

#### [MODIFY] [app_bootstrap.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/app_bootstrap.dart)
- Verify `AndroidAlarmManager.initialize()` is called before `NotificationService.init()`.

## Verification Plan

### Manual Verification
1. **Background FCM**: Send a test message via Firebase Console while the app is closed. Verify the notification appears.
2. **Offline Reminders**: Schedule an appointment for 1 hour and 5 minutes from now. Close the app. Verify the "1 Hour" reminder triggers correctly.
3. **Navigation**: Tap the background notification and verify it opens the correct appointment detail screen.
