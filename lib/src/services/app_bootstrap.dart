import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../firebase_options.dart';
import 'app_preferences.dart';
import 'notification_service.dart';

class AppBootstrapService {
  AppBootstrapService({
    Future<void> Function()? firebaseInitializer,
    Future<void> Function()? authInitializer,
    Future<void> Function()? storageInitializer,
    Future<void> Function()? notificationInitializer,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _firebaseInitializer =
           firebaseInitializer ?? _defaultFirebaseInitializer,
       _authInitializer = authInitializer ?? _defaultAuthInitializer,
       _storageInitializer = storageInitializer ?? _defaultStorageInitializer,
       _notificationInitializer =
           notificationInitializer ?? _defaultNotificationInitializer,
       _onError = onError ?? _defaultErrorHandler;

  final Future<void> Function() _firebaseInitializer;
  final Future<void> Function() _authInitializer;
  final Future<void> Function() _storageInitializer;
  final Future<void> Function() _notificationInitializer;
  final void Function(Object error, StackTrace stackTrace) _onError;

  Future<bool> initializeFirebase() async {
    try {
      await _firebaseInitializer();
      return true;
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
      return false;
    }
  }

  Future<void> initializeAppServices({
    bool runNotificationsInBackground = true,
  }) async {
    // Await Firebase initialization so that Firebase features (Auth, Firestore, etc.)
    // are fully set up before the UI starts building and attempting to access them.
    await initializeFirebase();

    // Initialize lightweight services (auth/storage) needed for immediate UI.
    final authFuture = _initializeAuth();
    final storageFuture = _initializeStorage();
    await Future.wait([authFuture, storageFuture]);

    if (runNotificationsInBackground) {
      unawaited(_initializeNotifications());
      return;
    }

    await _initializeNotifications();
  }

  Future<void> _initializeAuth() async {
    try {
      await _authInitializer();
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  Future<void> _initializeStorage() async {
    try {
      await _storageInitializer();
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationInitializer();
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  static Future<void> _defaultFirebaseInitializer() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Explicitly enable offline persistence settings for Cloud Firestore
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } on PlatformException catch (error) {
      if (error.message?.contains('Failed to load FirebaseOptions') == true) {
        debugPrint(
          'Firebase configuration is missing at runtime: ${error.message}',
        );
        return;
      }
      rethrow;
    } catch (error) {
      // If initialization fails for any reason (missing options on some platforms),
      // surface a debug message but don't crash startup.
      debugPrint('Firebase.initializeApp() failed: $error');
    }
  }

  static Future<void> _defaultAuthInitializer() async {
    await AppPreferences.instance.prefs;
  }

  static Future<void> _defaultStorageInitializer() async {
    await AppPreferences.instance.prefs;
  }

  static Future<void> _defaultNotificationInitializer() async {
    final supportedPlatform = defaultTargetPlatform;
    if (supportedPlatform != TargetPlatform.android &&
        supportedPlatform != TargetPlatform.iOS &&
        supportedPlatform != TargetPlatform.macOS) {
      return;
    }

    await NotificationService().init();
  }

  static void _defaultErrorHandler(Object error, StackTrace stackTrace) {
    debugPrint('Startup initialization failed: $error');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stackTrace, label: 'startup-init');
    }
  }
}
