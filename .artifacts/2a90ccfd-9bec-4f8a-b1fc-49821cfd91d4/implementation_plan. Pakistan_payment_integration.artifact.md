# Implementation Plan - Secure Payment Gateway Integration (Pakistan)

This plan outlines the architecture for integrating Pakistani payment gateways (Safepay/PayFast) with bank-grade security for API keys using `flutter_dotenv`.

## User Review Required

> [!IMPORTANT]
> To ensure "bank-grade" security, the `.env` file containing production keys **MUST NEVER** be committed to Git. I will provide a `.env.example` for team collaboration, but the actual `.env` will be strictly local or handled via CI/CD secrets.

## Proposed Changes

### [Core Configuration]

#### [MODIFY] [pubspec.yaml](file:///D:/Android/Booking-appointment-system-mobile-app/pubspec.yaml)
- Add `flutter_dotenv: ^5.1.0` to dependencies.
- Register the `.env` file as an asset so it's bundled with the app.

#### [MODIFY] [.gitignore](file:///D:/Android/Booking-appointment-system-mobile-app/.gitignore)
- Add `.env` to the ignore list to prevent accidental exposure of production keys.

#### [NEW] [.env.example](file:///D:/Android/Booking-appointment-system-mobile-app/.env.example)
- Create a template file showing the required keys (e.g., `SAFEPAY_API_KEY`, `PAYFAST_MERCHANT_ID`) without values.

### [Main Entry Point]

#### [MODIFY] [main.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/main.dart)
- Initialize `dotenv` before `runApp` to ensure keys are available throughout the app lifecycle.

### [Payment Architecture]

#### [NEW] [payment_gateway_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/services/payment_gateway_service.dart)
- Implement a `PaymentGatewayService` class.
- Securely read keys using `dotenv.get()`.
- Provide method skeletons for Pakistani gateway flows (e.g., `initializePayment`, `verifyTransaction`).
- Include `// REMOVE:` instructions for Safepay and PayFast specific setup.

## Verification Plan

### Manual Verification
1. **Asset Loading**: Verify the app starts without errors related to missing assets.
2. **Environment Variable Access**: Verify (via temporary debug prints) that keys from the `.env` file are correctly read by the service.
3. **Git Hygiene**: Run `git check-ignore .env` to confirm the security layer is active.
