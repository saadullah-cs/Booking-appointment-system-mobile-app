# Implementation Plan - Fix Crashes, Auth Loops, and Security Lock

This plan addresses the `BookingScreen` crash, the Firebase `invalid-credential` loop, and restores the PIN/Biometric lock functionality.

## Proposed Changes

### [Feature: Appointments]

#### [MODIFY] [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- Clean up `dispose()` method.
- Remove redundant calls to `_emailController.dispose()`, `_nameController.dispose()`, `_phoneController.dispose()`, and `_professionController.dispose()`.
- Ensure all controllers are disposed exactly once to prevent the "used after being disposed" crash.

---

### [Feature: Auth & Routing]

#### [MODIFY] [app_router.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/routes/app_router.dart)
- Update the `/` route to point to `SplashEntryScreen` instead of `LoginScreen`.
- This ensures that the app always starts with the splash screen logic which checks for existing sessions and security locks.

#### [MODIFY] [splash_entry_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/auth/screens/splash_entry_screen.dart)
- Enhance `invalid-credential` error handling.
- When this error occurs, explicitly clear `local_auth_current_user` from `AppPreferences` and call `FirebaseAuth.instance.signOut()`.
- Add a final fallback to `context.go('/login')` if any auth validation fails.

#### [MODIFY] [app_shell_scaffold.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/shared/widgets/app_shell_scaffold.dart)
- Review the `didChangeAppLifecycleState` logic to ensure `security_unlocked` is reset to `false` when the app is paused.
- Ensure `_checkPinLockOnResume()` is called reliably to trigger the `SecurityLockScreen`.

## Verification Plan

### Automated Tests
- N/A (Manual verification on physical device/emulator is preferred for lifecycle and auth loops).

### Manual Verification
1. **Crash Fix**: Open `BookingScreen`, fill details, then exit the screen. Verify no crash occurs in the debug console during disposal.
2. **Auth Loop**: Simulate an invalid credential state (e.g., by deleting the user in Firebase Console). Verify the app routes to the Login screen instead of spinning at the splash.
3. **Security Lock**: Enable PIN lock in Settings. Close the app and restart. Verify `SecurityLockScreen` appears. Minimize the app and resume. Verify `SecurityLockScreen` appears.
