# Implementation Plan - Memory & UX Optimizations

This plan covers a comprehensive performance sweep to resolve a 500MB RAM leak, optimize image memory, and improve navigation UX.

## User Review Required

> [!IMPORTANT]
> **PopScope & Navigation**: Back button interception will now ensure users are routed to the Dashboard or prompted before exiting. This adds a safety layer to the Android hardware back button.
>
> **Memory Management**: I will enforce strict disposal patterns and image caching constraints. Using `cacheWidth`/`cacheHeight` is critical for high-res posture photos.

## Proposed Changes

### [Memory Leak Fixes (Disposal)]

#### [MODIFY] Multiple StatefulWidgets
Ensure all controllers (Text, Scroll, Animation) and focus nodes are disposed of.
- [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- [vision_analyzer_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/vision_analyzer/vision_analyzer_screen.dart)
- [chat_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/chat/chat_screen.dart)
- [calculator_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/calculator/calculator_screen.dart)

### [Image Memory Management]

#### [MODIFY] Feature Screens
Add `cacheWidth` or `cacheHeight` to all `Image.file` and `Image.network` calls.
- **Posture Photos**: Limit to 800px width.
- **Avatars**: Limit to 200px width.

### [UX: Back Button Interception]

#### [MODIFY] [app_shell_scaffold.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/shared/widgets/app_shell_scaffold.dart)
- Wrap `Scaffold` in `PopScope`.
- Implement logic to route to `/dashboard` or show exit `AlertDialog`.

### [UX: Resumable Payments]

#### [MODIFY] Dashboard & List Screens
- Update appointment cards to show "Pay Now" for `pending` online payments.
- [staff_dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/staff_dashboard_screen.dart)
- [dashboard_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/dashboard/dashboard_screen.dart)
- [appointments_list_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointments_list_screen.dart)

### [Production Cleanup]
- Replace `print` with `debugPrint`.
- Remove unused imports.
- Add `const` where missing.

## Verification Plan

### Manual Verification
1. **Memory**: Use DevTools Memory profiler. Book multiple appointments and verify RAM doesn't climb linearly.
2. **Back Button**: Test on Android hardware back from Book/Notes/Profile. Verify routing to Dashboard. Test on Dashboard for Exit Dialog.
3. **Payment**: Verify "Pay Now" button functionality on a pending online appointment.
