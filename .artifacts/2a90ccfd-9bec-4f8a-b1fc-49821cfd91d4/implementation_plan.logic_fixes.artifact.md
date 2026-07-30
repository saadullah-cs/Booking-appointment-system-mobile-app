# Implementation Plan - Logic Fixes (Offline, Alarms, Payments)

This plan addresses three critical areas identified in QA: offline reliability, background alarm accuracy, and payment gateway security.

## User Review Required

> [!IMPORTANT]
> **Deep Linking Setup**: To support payment callbacks, I will register the `gct-clinic://` custom scheme in `AndroidManifest.xml`. Ensure your Safepay/PayFast dashboard is configured to redirect to `gct-clinic://payment-callback?status=success&id={order_id}`.

## Proposed Changes

### [Core Dependencies]

#### [MODIFY] [pubspec.yaml](file:///D:/Android/Booking-appointment-system-mobile-app/pubspec.yaml)
- Add `connectivity_plus: ^6.0.3`.

### [Android Platform Configuration]

#### [MODIFY] [AndroidManifest.xml](file:///D:/Android/Booking-appointment-system-mobile-app/android/app/src/main/AndroidManifest.xml)
- Verify `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM` permissions.
- Add `<intent-filter>` for `gct-clinic` scheme to handle payment callbacks.

### [Notification & Connectivity Service]

#### [MODIFY] [notification_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/notification_service.dart)
- Implement `_initConnectivityListener()` to detect internet restoration.
- If an appointment was booked offline, show the restoration toast and notification: "Your internet is restored and your appointment is officially confirmed!"
- Refine `scheduleAppointmentReminders` to ensure exactness for close-proximity bookings.

### [Feature: Appointments & Payments]

#### [MODIFY] [appointment_repository.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointment_repository.dart)
- Update `saveAppointment` to return a `bool` indicating if the remote Firestore write succeeded or timed out.

#### [MODIFY] [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- **Offline Logic**: Display "Saved offline as unstable internet..." toast on timeout.
- **Payment Gateway Fix**:
    - Save appointment as `pending` *before* launching the URL.
    - Set up a listener for the `/payment-callback` route to update the appointment status to `paid`.

#### [MODIFY] [app_router.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/routes/app_router.dart)
- Add `/payment-callback` route to handle redirects from the payment gateway.

## Verification Plan

### Manual Verification
1. **Offline Booking**: Disable internet, book appointment. Verify the "Saved offline" toast appears. Enable internet, verify "Internet restored" toast and notification appear.
2. **Exact Alarm**: Book an appointment 2 minutes before the 1-hour mark (e.g. 58 mins from now). Verify the alarm triggers exactly at the 1-hour mark.
3. **Payment Loophole**: Select Online Payment. Book. Verify status is `pending` on dashboard. Manually trigger the deep link `gct-clinic://payment-callback?status=success&id=GCT-NSR-XXXX` and verify status changes to `PAID`.
