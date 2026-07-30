# Walkthrough - Dual Payment Mode (Online & Cash)

I have implemented a dual payment selection flow in the appointment booking screen, supporting both secure online payments (Safepay/PayFast) and cash payments at the clinic.

## Changes Made

### 1. Model Enhancements
- **[appointment.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/models/appointment.dart)**: Added `paymentMethod`, `paymentStatus`, and `amount` fields to track transaction details for every appointment.
    - `paymentMethod`: 'online' or 'cash'.
    - `paymentStatus`: 'paid' (for online) or 'pending' (for cash).

### 2. Provider Integration
- **[repository_providers.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/repository_providers.dart)**: Registered the `paymentGatewayServiceProvider` to allow the booking screen to interact with the payment logic.

### 3. Booking Screen UI & Logic
- **[booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)**:
    - **Treatment Pricing**: Implemented a realistic PKR pricing model for chiropractic services (e.g., Gonstead Adjustment: 5,000 PKR).
    - **Selection UI**: Added professional selection cards in the confirmation step (Step 2) using `AnimatedContainer` for a smooth user experience.
    - **Dual Flow**:
        - **Cash**: Directly confirms the appointment with a `pending` payment status.
        - **Online**: Initializes a transaction via `PaymentGatewayService` and sets the status to `paid` upon simulation success.

## Verification Results

- ✅ `Appointment` model correctly handles payment metadata.
- ✅ UI allows seamless toggling between "Pay Online Now" and "Pay at Clinic".
- ✅ Total Fee is clearly displayed in the booking summary.
- ✅ Logic correctly differentiates between `paid` and `pending` statuses based on the selected mode.

> [!TIP]
> The online payment flow currently uses a skeleton initialization. In your production environment, you would use the `checkoutUrl` returned by the `PaymentGatewayService` to redirect the user to the gateway's hosted page.
