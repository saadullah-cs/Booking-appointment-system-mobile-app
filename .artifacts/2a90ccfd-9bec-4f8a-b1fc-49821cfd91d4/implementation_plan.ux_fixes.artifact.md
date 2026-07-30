# Implementation Plan - UX Fixes (Back Button & Payment Retry)

This plan addresses two major UX issues identified in QA: accidental app closures on Android and the inability to retry failed online payments.

## User Review Required

> [!IMPORTANT]
> **PopScope Interaction**: The back button interception will apply to the main navigation tabs. Sub-screens (like Appointment Details) will still pop normally using the system default or the app bar back button.
>
> **Payment Lifecycle**: Retrying a payment will use the same `PaymentGatewayService` but will keep the original appointment ID to maintain data integrity.

## Proposed Changes

### [Feature: App Shell]

#### [MODIFY] [app_shell_scaffold.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/shared/widgets/app_shell_scaffold.dart)
- Wrap the `Scaffold` with `PopScope`.
- Implement `onPopInvoked` logic:
    - If `currentRoute != '/dashboard'`, navigate to `/dashboard` and prevent pop.
    - If `currentRoute == '/dashboard'`, show a native `AlertDialog` asking for confirmation to exit.

### [Feature: Dashboard & Appointments]

#### [MODIFY] [staff_dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/staff_dashboard_screen.dart)
- Update `_buildAppointmentsList` item builder.
- Add a "Pay Now" button if `paymentMethod == 'online'` and `paymentStatus == 'pending'`.
- Connect button to `PaymentGatewayService`.

#### [MODIFY] [dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/dashboard_screen.dart)
- Update `_AppointmentTile` and `_NextAppointmentCard` to include the "Pay Now" retry action for pending online payments.

#### [MODIFY] [appointments_list_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointments_list_screen.dart)
- Update `_AppointmentListView` item builder to show the "Pay Now" button for eligible appointments.

## Verification Plan

### Manual Verification
1. **Back Button**:
    - Navigate to Profile. Press hardware back. Verify it goes to Dashboard.
    - On Dashboard, press hardware back. Verify "Exit App?" dialog appears.
    - Select 'Cancel' (stays in app) vs 'Exit' (closes app).
2. **Payment Retry**:
    - Book an online appointment but don't complete payment (it stays `pending`).
    - Locate the appointment on the dashboard.
    - Verify the "Pay Now" button is visible.
    - Tap "Pay Now" and verify it re-launches the gateway (or test mode dialog).
