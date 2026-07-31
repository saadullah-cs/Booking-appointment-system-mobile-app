import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class SecurityService {
  static const _channel = MethodChannel('com.gonsteadchiropractic.gct/security');

  /// Prevents screenshots and screen recording on mobile platforms (FLAG_SECURE on Android).
  static Future<void> preventScreenshots(bool prevent) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('preventScreenshots', {'prevent': prevent});
    } catch (e) {
      debugPrint('SecurityService preventScreenshots error: $e');
    }
  }
}
