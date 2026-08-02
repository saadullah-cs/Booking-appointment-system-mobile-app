# Implementation Plan - Booking Flow & Status Filtering Fixes

This plan outlines the fixes for the appointment booking success flow, status filtering logic, and the addition of a cancellation feature.

## Proposed Changes

### [Core: Cleanup]

#### [MODIFY] [dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/dashboard_screen.dart)
- Remove the 'Test Notif' button from the Quick Actions grid.

#### [MODIFY] [notification_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/notification_service.dart)
- Remove the `testZonedNotification` method.

### [Feature: Booking Success Flow]

#### [MODIFY] [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- In `_submitBooking`, after a successful save:
    - Trigger a `SnackBar` with the message "Appointment booked successfully!".
    - Navigate back to the 'Upcoming' tab in the Appointments view using `context.go('/appointments')`.
    - Ensure this happens for both online and cash payment modes.

### [Feature: Appointments Filtering]

#### [MODIFY] [appointments_list_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointments_list_screen.dart)
- Update `filterByType` logic to strictly follow these rules:
    - **Upcoming**: `(status == 'Pending' || status == 'Confirmed') && scheduledAt.isAfter(now)`.
    - **Past**: `(status == 'Completed' || status == 'No Show') || (scheduledAt != null && scheduledAt.isBefore(now))`.
    - **Cancelled**: `status == 'Cancelled'`.

### [Feature: Appointment Cancellation]

#### [MODIFY] [appointment_detail_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointment_detail_screen.dart)
- Add a prominent "Cancel Appointment" button in the quick action buttons area.
- Ensure it calls `_updateStatus('Cancelled')`.

#### [MODIFY] [appointments_list_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointments_list_screen.dart)
- Add a "Cancel" `IconButton` to the appointment card for quick access.
- Hook it up to a new `_cancelAppointment` method that updates the status to 'Cancelled'.

## Verification Plan

### Manual Verification
1. **Cleanup**: Verify the 'Test Notif' button is no longer on the Dashboard.
2. **Booking Flow**: Book a new appointment. Verify the "Appointment booked successfully!" SnackBar appears and you are redirected to the Appointments screen.
3. **Filtering**:
    - Verify 'Pending' appointments for today/future appear in 'Upcoming'.
    - Verify past appointments appear in 'Past'.
    - Verify 'Completed'/'No Show' appear in 'Past'.
    - Verify 'Cancelled' appear in 'Cancelled'.
4. **Cancellation**:
    - Cancel an appointment from the list or detail screen.
    - Verify it immediately moves to the 'Cancelled' tab.
