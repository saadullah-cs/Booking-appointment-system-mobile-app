# Implementation Plan - Native Notification Logic Refactor

This plan outlines refactoring the notification system to use native `flutter_local_notifications` scheduling instead of `AndroidAlarmManager`, ensuring reminders trigger even when the app is swiped away from RAM.

## User Review Required

> [!IMPORTANT]
> To reliably use `tz.local` and `setLocalLocation()`, I will add the `flutter_timezone` package. This allows the app to detect the device's actual timezone name and configure the `timezone` library accordingly.

## Proposed Changes

### [Core Dependencies]

#### [MODIFY] [pubspec.yaml](file:///D:/Android/Booking-appointment-system-mobile-app/pubspec.yaml)
- Add `flutter_timezone: ^2.0.0` to dependencies.

### [Android Platform Configuration]

#### [MODIFY] [AndroidManifest.xml](file:///D:/Android/Booking-appointment-system-mobile-app/android/app/src/main/AndroidManifest.xml)
- Verify/Add `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` permissions.
- Ensure `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver` are correctly declared within the `<application>` tag.
- Remove `AndroidAlarmManager` receivers and services if no longer needed (the user only asked to refactor appointment reminders, but if we move away from AlarmManager entirely for notifications, we can clean this up. I will keep them for now but focus on using `zonedSchedule`).

### [Main Entry Point]

#### [MODIFY] [main.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/main.dart)
- Initialize timezones using `tz.initializeTimeZones()`.
- Detect local timezone using `FlutterTimezone.getLocalTimezone()`.
- Set local location using `tz.setLocalLocation(tz.getLocation(timeZoneName))`.

### [Notification Service]

#### [MODIFY] [notification_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/notification_service.dart)
- **Permissions**: Add `requestNotificationsPermission()` and `requestExactAlarmsPermission()` to the `init()` method.
- **Refactor `scheduleLocalNotification`**:
    - Remove `AndroidAlarmManager.oneShotAt()` logic.
    - Use `tz.TZDateTime.from(scheduledDate, tz.local)` for `zonedSchedule`.
    - Configure `AndroidScheduleMode.exactAllowWhileIdle`.
- **Cleanup**: Remove `_alarmCallback` and other unused `AndroidAlarmManager` related code if they are no longer serving notifications.

## Verification Plan

### Manual Verification
1. **Timezone Init**: Verify logs show successful timezone detection and initialization in `main.dart`.
2. **Permissions**: Ensure the app prompts for "Exact Alarm" and "Notification" permissions on first launch (Android 13+).
3. **Scheduled Reminder**:
    - Book an appointment for 1 hour and 5 minutes from now.
    - Swipe the app away from RAM.
    - Verify the notification appears exactly 1 hour before the appointment.
4. **Boot Reliability**: (Optional) Reboot the device and verify that scheduled notifications are restored (requires `ScheduledNotificationBootReceiver`).
