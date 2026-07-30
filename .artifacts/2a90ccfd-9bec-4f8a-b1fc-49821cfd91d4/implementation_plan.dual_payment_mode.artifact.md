# Implementation Plan - Dual Payment Mode (Online & Cash)

This plan outlines the integration of a dual payment selection flow in the appointment booking screen, supporting both online (Safepay/PayFast) and cash payments.

## User Review Required

> [!IMPORTANT]
> The "Online Payment" mode will initialize a transaction using the `PaymentGatewayService`. For this phase, I will simulate the success response and set the payment status to 'paid'. In a real production scenario, the app should navigate to the checkout URL provided by the gateway.
>
> I will also add a `price` field to the booking flow to show the user what they are paying for.

## Proposed Changes

### [Models]

#### [MODIFY] [appointment.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/models/appointment.dart)
- Add `paymentMethod` (String: 'online' | 'cash').
- Add `paymentStatus` (String: 'paid' | 'pending').
- Add `amount` (double).
- Update serialization logic (`fromJson`, `toJson`, `copyWith`).

### [Providers]

#### [MODIFY] [repository_providers.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/repository_providers.dart)
- Add `paymentGatewayServiceProvider` to allow the UI to interact with the payment service.

### [Features: Appointments]

#### [MODIFY] [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- Define `PaymentMode` enum.
- Add `_paymentMode` state to Step 2.
- Implement `_buildPaymentSelection` widget with radio-style selection cards for "Pay Online" and "Pay at Clinic".
- Update `_submitBooking` to:
    - Handle online payment initialization if selected.
    - Set the appropriate `paymentStatus` and `paymentMethod` in the saved appointment.
- Display the service price in the confirmation summary.

## Verification Plan

### Manual Verification
1. **Selection UI**: Go to the confirmation step (Step 2) and verify the two payment options are clearly visible and toggleable.
2. **Cash Flow**: Select "Pay at Clinic" and confirm. Verify the appointment is saved with status `pending`.
3. **Online Flow**: Select "Pay Online" and confirm. Verify the simulated payment initialization occurs and the appointment is saved with status `paid`.
4. **Data Integrity**: Inspect the saved appointment data (via logs or Detail screen if updated) to ensure `paymentMethod` and `paymentStatus` are correct.
