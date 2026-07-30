import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../firebase_options.dart';
import '../../models/app_user.dart';
import '../../services/app_preferences.dart';

class AuthRepository {
  AuthRepository() : _prefsFuture = AppPreferences.instance.prefs {
    _initDefaultUser();
    _startSessionValidationTimer();
  }

  final Future<SharedPreferences> _prefsFuture;
  final StreamController<AppUser?> _authStateController =
      StreamController<AppUser?>.broadcast();

  static const String _currentUserKey = 'local_auth_current_user';
  static const String _usersKey = 'local_auth_registered_users';

  AppUser? _cachedUser;
  Timer? _sessionValidationTimer;

  void _startSessionValidationTimer() {
    _sessionValidationTimer?.cancel();
    _sessionValidationTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      try {
        if (Firebase.apps.isNotEmpty &&
            FirebaseAuth.instance.currentUser != null) {
          try {
            await FirebaseAuth.instance.currentUser!.reload();
          } on FirebaseAuthException catch (e) {
            debugPrint(
              'Periodic Firebase session check failed (code: ${e.code})',
            );
            if (e.code == 'user-not-found' ||
                e.code == 'user-disabled' ||
                e.code == 'invalid-credential') {
              await signOut();
            }
          }
        }
      } catch (_) {}
    });
  }

  /// Try to initialize Firebase on-demand. Returns true when Firebase is available.
  Future<bool> _ensureFirebaseInitialized() async {
    try {
      if (Firebase.apps.isNotEmpty) return true;
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return Firebase.apps.isNotEmpty;
    } catch (error) {
      // Not available or misconfigured; log and continue with local auth.
      try {
        debugPrint('Firebase initialization failed: $error');
      } catch (_) {}
      return false;
    }
  }

  bool get _firebaseEnabled {
    try {
      // Firebase.apps may throw if Firebase is not configured; handle gracefully.
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Stream<AppUser?> authStateChanges() {
    // Load initial user state
    _loadPersistedUser().then(_authStateController.add);

    // Attempt to initialize Firebase in background and subscribe to auth changes if available.
    _ensureFirebaseInitialized().then((available) {
      if (!available) return;
      FirebaseAuth.instance.authStateChanges().listen((firebaseUser) async {
        if (firebaseUser == null) {
          final localUser = await _loadPersistedUser();
          if (localUser != null) {
            _cachedUser = localUser;
            _authStateController.add(localUser);
            return;
          }

          _cachedUser = null;
          _authStateController.add(null);
          final prefs = await _prefsFuture;
          await prefs.remove(_currentUserKey);
          return;
        }

        final user = AppUser(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName:
              firebaseUser.displayName ?? firebaseUser.email ?? 'Patient',
          phoneNumber: firebaseUser.phoneNumber ?? '',
        );

        final prefs = await _prefsFuture;
        await _persistUser(user, prefs);
      });
    });

    return _authStateController.stream;
  }

  AppUser? get currentUser {
    if (_cachedUser != null) return _cachedUser;
    if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
      final firebaseUser = FirebaseAuth.instance.currentUser!;
      return AppUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        displayName:
            firebaseUser.displayName ?? firebaseUser.email ?? 'Patient',
        phoneNumber: firebaseUser.phoneNumber ?? '',
      );
    }
    return null;
  }

  Future<AppUser> _signInLocally(String email, String password) async {
    final prefs = await _prefsFuture;
    final usersJson = prefs.getString(_usersKey);
    final registeredUsers = <String, Map<String, dynamic>>{};

    if (usersJson != null) {
      final decoded = jsonDecode(usersJson) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        registeredUsers[entry.key] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }

    final normalizedEmail = email.trim().toLowerCase();
    final storedUser = registeredUsers[normalizedEmail];
    if (storedUser == null || storedUser['password'] != password) {
      throw Exception('Invalid credentials');
    }

    final user = AppUser.fromJson(
      Map<String, dynamic>.from(storedUser)..remove('password'),
    );
    await _persistUser(user, prefs);
    return user;
  }

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (await _ensureFirebaseInitialized()) {
      try {
        final credentials = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        final firebaseUser = credentials.user!;
        final user = AppUser(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName:
              firebaseUser.displayName ?? firebaseUser.email ?? 'Patient',
          phoneNumber: firebaseUser.phoneNumber ?? '',
        );

        final prefs = await _prefsFuture;
        await _persistUser(user, prefs);
        await _saveUserLocally(email, password, user);

        return user;
      } on FirebaseAuthException catch (error) {
        debugPrint('Firebase sign-in failed (code: ${error.code})');
        try {
          debugPrint('Trying local auth fallback...');
          return await _signInLocally(email, password);
        } catch (_) {
          throw Exception(error.message ?? 'Firebase login failed');
        }
      } catch (error) {
        debugPrint('Firebase sign-in failed, trying local auth: $error');
        return _signInLocally(email, password);
      }
    }

    return _signInLocally(email, password);
  }

  Future<AppUser> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    if (await _ensureFirebaseInitialized()) {
      try {
        final credentials = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        final firebaseUser = credentials.user!;
        final displayName = name.trim().isEmpty ? 'Patient' : name.trim();
        await firebaseUser.updateDisplayName(displayName);
        await firebaseUser.reload();

        final user = AppUser(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName ?? displayName,
          phoneNumber: firebaseUser.phoneNumber ?? '',
        );
        await _persistUser(user, await _prefsFuture);
        return user;
      } on FirebaseAuthException catch (error) {
        throw Exception(error.message ?? 'Firebase registration failed');
      } catch (error) {
        debugPrint(
          'Firebase registration failed, falling back to local register: $error',
        );
      }
    }

    final prefs = await _prefsFuture;
    final usersJson = prefs.getString(_usersKey);
    final registeredUsers = <String, Map<String, dynamic>>{};

    if (usersJson != null) {
      final decoded = jsonDecode(usersJson) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        registeredUsers[entry.key] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }

    final normalizedEmail = email.trim().toLowerCase();
    if (registeredUsers.containsKey(normalizedEmail)) {
      throw Exception('An account with this email already exists');
    }

    final user = AppUser(
      uid: DateTime.now().microsecondsSinceEpoch.toString(),
      email: normalizedEmail,
      displayName: name.trim().isEmpty ? 'Patient' : name.trim(),
      phoneNumber: '',
    );

    registeredUsers[normalizedEmail] = {...user.toJson(), 'password': password};
    await prefs.setString(_usersKey, jsonEncode(registeredUsers));
    await _persistUser(user, prefs);
    return user;
  }

  Future<void> sendPasswordReset({required String email}) async {
    if (_firebaseEnabled) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        return;
      } on FirebaseAuthException catch (error) {
        throw Exception(error.message ?? 'Failed to send password reset email');
      }
    }

    await Future<void>.value();
  }

  Future<AppUser?> signInWithGoogle() async {
    if (await _ensureFirebaseInitialized()) {
      try {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          throw Exception('Google sign-in was cancelled.');
        }

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
          accessToken: googleAuth.accessToken,
        );

        final signInResult = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        final firebaseUser = signInResult.user!;
        final user = AppUser(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName:
              firebaseUser.displayName ?? firebaseUser.email ?? 'Google User',
          phoneNumber: firebaseUser.phoneNumber ?? '',
        );
        await _persistUser(user, await _prefsFuture);
        return user;
      } on FirebaseAuthException catch (error) {
        throw Exception(error.message ?? 'Google sign-in failed');
      } catch (error) {
        debugPrint('Google sign-in failed, falling back to local stub: $error');
      }
    }

    final prefs = await _prefsFuture;
    final user = AppUser(
      uid: 'google-${DateTime.now().microsecondsSinceEpoch}',
      email: 'google-user@local.app',
      displayName: 'Google User',
      phoneNumber: '',
    );
    await _persistUser(user, prefs);
    return user;
  }

  Future<void> signOut() async {
    if (_firebaseEnabled) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }

    final prefs = await _prefsFuture;
    await prefs.remove(_currentUserKey);
    await prefs.remove('security_unlocked');
    _cachedUser = null;
    _authStateController.add(null);
  }

  Future<void> updateUserProfileName(String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;

    if (await _ensureFirebaseInitialized() &&
        FirebaseAuth.instance.currentUser != null) {
      try {
        await FirebaseAuth.instance.currentUser!.updateDisplayName(cleanName);
        await FirebaseAuth.instance.currentUser!.reload();
      } catch (e) {
        debugPrint('Failed to update display name on Firebase: $e');
      }
    }

    if (_cachedUser != null) {
      final updatedUser = _cachedUser!.copyWith(displayName: cleanName);
      final prefs = await _prefsFuture;
      await _persistUser(updatedUser, prefs);

      // Also update in registered users map locally so next sign-in has it
      final usersJson = prefs.getString(_usersKey);
      if (usersJson != null) {
        try {
          final decoded = jsonDecode(usersJson) as Map<String, dynamic>;
          final normalizedEmail = updatedUser.email.toLowerCase();
          if (decoded.containsKey(normalizedEmail)) {
            final userMap = Map<String, dynamic>.from(
              decoded[normalizedEmail] as Map,
            );
            userMap['displayName'] = cleanName;
            decoded[normalizedEmail] = userMap;
            await prefs.setString(_usersKey, jsonEncode(decoded));
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _persistUser(AppUser user, SharedPreferences prefs) async {
    await prefs.setString(_currentUserKey, jsonEncode(user.toJson()));
    _cachedUser = user;
    _authStateController.add(user);
  }

  Future<AppUser?> _loadPersistedUser() async {
    if (_firebaseEnabled && FirebaseAuth.instance.currentUser != null) {
      final firebaseUser = FirebaseAuth.instance.currentUser!;
      final user = AppUser(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        displayName:
            firebaseUser.displayName ?? firebaseUser.email ?? 'Patient',
        phoneNumber: firebaseUser.phoneNumber ?? '',
      );
      _cachedUser = user;
      return user;
    }

    final prefs = await _prefsFuture;
    final storedUser = prefs.getString(_currentUserKey);
    if (storedUser == null || storedUser.isEmpty) {
      _cachedUser = null;
      return null;
    }

    final user = AppUser.fromJson(
      jsonDecode(storedUser) as Map<String, dynamic>,
    );
    // If Firebase is enabled, but we are not logged into Firebase,
    // and the stored user is not one of our predefined local fallback accounts,
    // then this stored session is invalid (the Firebase user is signed out/deleted).
    if (_firebaseEnabled && FirebaseAuth.instance.currentUser == null) {
      final email = user.email.toLowerCase();
      final isLocalFallback =
          email == 'drbashir@gct.com' ||
          email == 'bashir@gmail.com' ||
          email == 'khan@gmail.com';
      if (!isLocalFallback) {
        await prefs.remove(_currentUserKey);
        _cachedUser = null;
        return null;
      }
    }

    _cachedUser = user;
    return user;
  }

  Future<void> _saveUserLocally(
    String email,
    String password,
    AppUser user,
  ) async {
    final prefs = await _prefsFuture;
    final usersJson = prefs.getString(_usersKey);
    final registeredUsers = <String, Map<String, dynamic>>{};

    if (usersJson != null) {
      try {
        final decoded = jsonDecode(usersJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          registeredUsers[entry.key] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      } catch (_) {}
    }

    final normalizedEmail = email.trim().toLowerCase();
    registeredUsers[normalizedEmail] = {...user.toJson(), 'password': password};
    await prefs.setString(_usersKey, jsonEncode(registeredUsers));
  }

  Future<void> _initDefaultUser() async {
    final prefs = await _prefsFuture;
    final usersJson = prefs.getString(_usersKey);
    final registeredUsers = <String, Map<String, dynamic>>{};

    if (usersJson != null) {
      try {
        final decoded = jsonDecode(usersJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          registeredUsers[entry.key] = Map<String, dynamic>.from(
            entry.value as Map,
          );
        }
      } catch (_) {}
    }

    // Ensure default doctor is registered
    if (!registeredUsers.containsKey('drbashir@gct.com')) {
      final defaultDoctor = AppUser(
        uid: 'doctor-bashir',
        email: 'drbashir@gct.com',
        displayName: 'Dr. Bashir Ahmad',
        phoneNumber: '+92 304 6996267',
      );
      registeredUsers['drbashir@gct.com'] = {
        ...defaultDoctor.toJson(),
        'password': 'password123',
      };
    }

    // Also ensure bashir@gmail.com is registered locally as fallback
    if (!registeredUsers.containsKey('bashir@gmail.com')) {
      final gmailDoctor = AppUser(
        uid: 'doctor-bashir-gmail',
        email: 'bashir@gmail.com',
        displayName: 'Dr. Bashir Ahmad',
        phoneNumber: '+92 304 6996267',
      );
      registeredUsers['bashir@gmail.com'] = {
        ...gmailDoctor.toJson(),
        'password': 'password123',
      };
    }

    // Also ensure khan@gmail.com is registered locally as fallback
    if (!registeredUsers.containsKey('khan@gmail.com')) {
      final khanUser = AppUser(
        uid: 'user-khan',
        email: 'khan@gmail.com',
        displayName: 'Khan',
        phoneNumber: '',
      );
      registeredUsers['khan@gmail.com'] = {
        ...khanUser.toJson(),
        'password': 'password123',
      };
    }

    await prefs.setString(_usersKey, jsonEncode(registeredUsers));
  }

  // --- Staff Portal Access & Credentials ---

  static const String _allowStaffViewKey = 'clinic_allow_staff_view';
  static const String _staffCredentialsKey = 'clinic_staff_credentials';

  Future<bool> getStaffViewToggle() async {
    if (await _ensureFirebaseInitialized()) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('clinic_config')
            .get();
        if (doc.exists && doc.data() != null) {
          final val = doc.data()?['allowStaffView'] != false;
          final prefs = await _prefsFuture;
          await prefs.setBool(_allowStaffViewKey, val);
          return val;
        }
      } catch (e) {
        debugPrint('Failed to get staff toggle online: $e');
      }
    }
    final prefs = await _prefsFuture;
    return prefs.getBool(_allowStaffViewKey) ?? true;
  }

  Future<void> setStaffViewToggle(bool enabled) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_allowStaffViewKey, enabled);

    if (await _ensureFirebaseInitialized()) {
      try {
        await FirebaseFirestore.instance
            .collection('settings')
            .doc('clinic_config')
            .set({'allowStaffView': enabled}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Failed to set staff toggle online: $e');
      }
    }
  }

  Future<List<Map<String, String>>> loadStaffCredentials() async {
    if (await _ensureFirebaseInitialized()) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('staff')
            .get();
        final list = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'email': doc.id,
            'password': data['password']?.toString() ?? '',
          };
        }).toList();

        // Sync to local cache
        final prefs = await _prefsFuture;
        await prefs.setString(_staffCredentialsKey, jsonEncode(list));
        return list;
      } catch (e) {
        debugPrint('Failed to load staff credentials online: $e');
      }
    }

    final prefs = await _prefsFuture;
    final jsonStr = prefs.getString(_staffCredentialsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonStr) as List;
      return decoded.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'email': map['email']?.toString() ?? '',
          'password': map['password']?.toString() ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addStaffCredential(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (await _ensureFirebaseInitialized()) {
      try {
        await FirebaseFirestore.instance
            .collection('staff')
            .doc(normalizedEmail)
            .set({
              'password': password,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      } catch (e) {
        debugPrint('Failed to save staff credential online: $e');
      }
    }

    // Save to local cache
    final list = await loadStaffCredentials();
    list.removeWhere((item) => item['email'] == normalizedEmail);
    list.add({'email': normalizedEmail, 'password': password});
    final prefs = await _prefsFuture;
    await prefs.setString(_staffCredentialsKey, jsonEncode(list));
  }

  Future<void> deleteStaffCredential(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (await _ensureFirebaseInitialized()) {
      try {
        await FirebaseFirestore.instance
            .collection('staff')
            .doc(normalizedEmail)
            .delete();
      } catch (e) {
        debugPrint('Failed to delete staff credential online: $e');
      }
    }

    // Update local cache
    final list = await loadStaffCredentials();
    list.removeWhere((item) => item['email'] == normalizedEmail);
    final prefs = await _prefsFuture;
    await prefs.setString(_staffCredentialsKey, jsonEncode(list));
  }
}
