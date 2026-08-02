# Implementation Plan - Notification UX & Logic Fixes

This plan addresses background notification reliability, state synchronization for completed appointments, and adds a rapid testing utility.

## User Review Required

> [!IMPORTANT]
> **Permissions**: `USE_EXACT_ALARM` is a high-privilege permission. I will ensure it is correctly declared.
> **State Management**: I will introduce a Riverpod `appointmentsProvider` to ensure the App Shell's notification badge and bottom sheet stay in sync with status changes made on other screens.

## Proposed Changes

### [Core: State Management]

#### [MODIFY] [appointment_repository.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointment_repository.dart)
- Implement `appointmentsProvider` (StateNotifier) to allow real-time UI updates when appointments are saved or updated.

### [Feature: App Shell]

#### [MODIFY] [app_shell_scaffold.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/shared/widgets/app_shell_scaffold.dart)
- Watch `appointmentsProvider`.
- Update `_filterUpcomingAppointments` to exclude 'Completed' and 'No Show' statuses.
- This ensures the notification badge and sheet immediately clear when an appointment is marked as done.

### [Feature: Dashboard]

#### [MODIFY] [dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/dashboard_screen.dart)
- Add a temporary `ElevatedButton` in the "Quick Actions" or top header labeled 'Test Background Notification'.
- Connect it to a new `NotificationService.testZonedNotification()` method.

### [Service: Notifications]

#### [MODIFY] [notification_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/notification_service.dart)
- Add `testZonedNotification()`: Schedules a notification for exactly 10 seconds in the future using `zonedSchedule`.

### [Android Platform]

#### [MODIFY] [AndroidManifest.xml](file:///D:/Android/Booking-appointment-system-mobile-app/android/app/src/main/AndroidManifest.xml)
- Enforce the presence of `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM`.

### [Bug Fixes]

#### [MODIFY] [appointment_detail_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointment_detail_screen.dart)
- Fix syntax error in `_DetailRow` (dangling `?trailing`).

## Verification Plan

### Manual Verification
1. **State Sync**: Open the Notifications sheet in `AppShellScaffold`. Note an upcoming appointment. Go to its detail screen and mark as "Completed". Return to Dashboard. Verify the notification is gone from the badge and sheet.
2. **Rapid Test**: Tap 'Test Background Notification'. Swipe the app away from RAM immediately. Wait 10 seconds. Verify the notification appears.
3. **Permissions**: Verify `USE_EXACT_ALARM` is declared in the merged manifest.
