# Implementation Plan - Booking & Payment Flow Critical Fixes

This plan outlines the implementation of four critical fixes to enhance offline reliability, integrate online payments, and provide financial insights on the dashboard.

## User Review Required

> [!IMPORTANT]
> **Offline Optimism**: The app will now navigate to the confirmation screen after a 3-second timeout if Firestore is unreachable. The data will sync automatically once the device is back online (handled by Firestore's persistence).
>
> **Online Payment**: "Pay Online Now" will attempt a real initialization. Since we are in a development environment, I will include a "Test Mode" dialog if the Safepay/PayFast keys are unconfigured in `.env`.

## Proposed Changes

### [Models & Repository]

#### [MODIFY] [appointment_repository.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointment_repository.dart)
- Add a 3-second `.timeout()` to the Firestore `set()` operation in `saveAppointment`.
- Ensure errors are caught so the local cache update still proceeds.

### [Feature: Appointments]

#### [MODIFY] [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- **Online Flow**: Implement logic to call `PaymentGatewayService.initializeSafepayTransaction` when "Confirm Booking" is pressed for online mode.
- **Gateway Bridge**: Launch a WebView or show a "Payment Gateway in Test Mode" dialog if keys are missing.
- **Submit Logic**: Update `_submitBooking` to handle the repository timeout and ensure immediate navigation.

#### [MODIFY] [appointments_list_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointments_list_screen.dart)
- Add a visual payment status badge (PAID / UNPAID) to each appointment card.

### [Feature: Dashboard]

#### [MODIFY] [staff_dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/staff_dashboard_screen.dart)
- **Revenue Metrics**: Add a `Payments Quick View` section.
    - **Total Revenue**: Sum of all appointment amounts.
    - **Collected**: Sum of 'paid' appointments.
    - **Pending**: Sum of 'pending' (cash) appointments.
- **Card Badges**: Add the same payment status badges to the dashboard appointment list.

## Verification Plan

### Manual Verification
1. **Offline Test**: Disable Wi-Fi, book an appointment. Verify the spinner stops after 3s and you land on the "Booked!" screen.
2. **Online Gateway**: Select "Pay Online". Verify the gateway initialization is triggered and the "Test Mode" dialog appears if no keys are found.
3. **Revenue Check**: Verify the dashboard revenue totals match the sum of appointments in the list.
4. **Badge Check**: Ensure online bookings show "PAID" (Green) and cash bookings show "UNPAID" (Orange).
