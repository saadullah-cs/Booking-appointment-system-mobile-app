# Implementation Plan - Extreme Image Compression for AI Posture Scanning

This plan outlines the integration of `flutter_image_compress` to reduce image sizes by ~80% (JPEG, 65% quality) across the AI posture scanning and appointment photo flows. This will optimize local storage and minimize future Firebase Storage costs.

## User Review Required

> [!IMPORTANT]
> The current codebase does not explicitly upload images to Firebase Storage. I will implement the compression immediately after image selection so that all subsequent operations (local display, PDF generation, or future Firebase integration) benefit from the reduced file size.

## Proposed Changes

### [Core Dependencies]

#### [MODIFY] [pubspec.yaml](file:///D:/Android/Booking-appointment-system-mobile-app/pubspec.yaml)
- Add `flutter_image_compress: ^2.3.0` to the dependencies.

### [Utilities]

#### [NEW] [image_service.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/utils/image_service.dart)
- Create a dedicated service for image operations to maintain professional architecture.
- Implement `compressPostureImage` using `flutter_image_compress`.
- Handle temporary file creation and cleanup of raw source files.

### [Feature: Vision Analyzer]

#### [MODIFY] [vision_analyzer_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/vision_analyzer/vision_analyzer_screen.dart)
- Integrate `ImageService` into the `_capture` workflow.
- Add `// REMOVE:` comments to guide the user through the compression and cleanup steps.

### [Feature: Appointments]

#### [MODIFY] [booking_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/booking_screen.dart)
- Update the posture photo capture logic (camera/gallery) to use the compression service.

#### [MODIFY] [appointment_detail_screen.dart](file:///D:/Android/Booking-appointment-system-mobile-app/lib/src/features/appointments/appointment_detail_screen.dart)
- Update the image picking logic in edit mode to include compression.

## Verification Plan

### Automated Tests
- No existing automated tests cover image picking, but I will ensure the code compiles and follows Flutter best practices.

### Manual Verification
1. **Vision Analyzer**: Capture an image and verify it is compressed (size check in logs if possible, or visual check).
2. **Booking/Detail Screens**: Pick a posture photo and ensure it displays correctly after compression.
3. **Cleanup**: Verify the raw file path is replaced by the compressed file path and original cache is cleared.
