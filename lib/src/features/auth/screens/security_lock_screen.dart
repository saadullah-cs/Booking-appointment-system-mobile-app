import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:go_router/go_router.dart';
import '../../../services/app_preferences.dart';
import 'dart:io';

import '../auth_providers.dart';
import '../../../models/app_user.dart';
import '../../../theme/app_theme.dart';

class SecurityLockScreen extends ConsumerStatefulWidget {
  const SecurityLockScreen({super.key});

  @override
  ConsumerState<SecurityLockScreen> createState() => _SecurityLockScreenState();
}

class _SecurityLockScreenState extends ConsumerState<SecurityLockScreen>
    with TickerProviderStateMixin {
  String _enteredPin = '';
  String _storedPin = '';
  bool _biometricEnabled = false;
  String? _imagePath;
  bool _isShaking = false;
  bool _isLoading = true;
  final LocalAuthentication _localAuth = LocalAuthentication();

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _loadData();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  Future<void> _loadData() async {
    final prefs = await AppPreferences.instance.prefs;
    final imagePath = prefs.getString('doctor_profile_image');
    final storedPin = prefs.getString('security_pin_code') ?? '';
    final bioEnabled = prefs.getBool('security_biometric_enabled') ?? false;

    setState(() {
      _imagePath = imagePath;
      _storedPin = storedPin;
      _biometricEnabled = bioEnabled;
      _isLoading = false;
    });

    // Auto-trigger biometric scan if enabled
    if (bioEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerBiometricScan();
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onNumberTap(String number) {
    if (_enteredPin.length >= 4) return;
    setState(() {
      _enteredPin += number;
    });

    if (_enteredPin.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _verifyPin() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (_enteredPin == _storedPin) {
      // Mark session as unlocked so splash won't redirect back here
      final prefs = await AppPreferences.instance.prefs;
      await prefs.setBool('security_unlocked', true);
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          context.go('/dashboard');
        }
      }
    } else {
      // Trigger shake animation
      setState(() => _isShaking = true);
      _shakeController.forward(from: 0).then((_) {
        setState(() {
          _enteredPin = '';
          _isShaking = false;
        });
      });
    }
  }

  Future<void> _triggerBiometricScan() async {
    try {
      final bool canAuthenticate =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuthenticate) {
        _showSnackBar(
          'Biometric authentication is not available on this device.',
          isError: true,
        );
        return;
      }

      final available = await _localAuth.getAvailableBiometrics();
      if (available.isEmpty) {
        _showSnackBar(
          'No biometrics enrolled. Please enroll a fingerprint on your device.',
          isError: true,
        );
        return;
      }

      // Allow device credential fallback (PIN/pattern) so users won't be blocked
      // if biometric hardware behaves unexpectedly.
      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock the app',
        options: const AuthenticationOptions(
          biometricOnly: false,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );

      if (authenticated && mounted) {
        // Mark session as unlocked so splash won't redirect back here
        final prefs = await AppPreferences.instance.prefs;
        await prefs.setBool('security_unlocked', true);
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          context.go('/dashboard');
        }
        return;
      }

      if (!authenticated && mounted) {
        _showSnackBar(
          'Authentication did not succeed. Please try again or use PIN.',
          isError: true,
        );
      }
    } on Exception catch (error) {
      debugPrint('Biometric auth error: $error');
      if (mounted) {
        _showSnackBar(
          'Biometric authentication failed. Please use your PIN.',
          isError: true,
        );
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cs = Theme.of(context).colorScheme;
    final authState = ref.watch(authStateProvider);
    final user =
        authState.asData?.value ??
        AppUser(
          uid: 'doctor-bashir',
          email: 'drbashir@gct.com',
          displayName: 'Dr. Bashir Ahmad',
          phoneNumber: '',
        );

    Widget avatar;
    if (_imagePath != null && _imagePath!.isNotEmpty) {
      avatar = Image.file(
        File(_imagePath!),
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          cacheWidth: 160,
          cacheHeight: 160,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.person_rounded, size: 40, color: Colors.white),
        ),
      );
    } else {
      avatar = Image.asset(
        'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
        width: 80,
        height: 80,
        fit: BoxFit.contain,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.person_rounded, size: 40, color: Colors.white),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // Slate Dark
              Color(0xFF1E293B), // Slate Medium
              Color(0xFF334155), // Slate Soft
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 10),

                // Doctor photo avatar
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  padding: const EdgeInsets.all(8),
                  child: avatar,
                ),
                const SizedBox(height: 14),

                // Title Display
                Text(
                  user.displayName.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter PIN to unlock app',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 28),

                // PIN Indicators
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final double offset = _isShaking
                        ? (12 *
                              (1.0 - _shakeAnim.value) *
                              (ref.read(authStateProvider).hashCode % 2 == 0
                                  ? 1
                                  : -1))
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (index) {
                          final filled = index < _enteredPin.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? (_isShaking
                                        ? Colors.redAccent
                                        : AppColors.primary)
                                  : Colors.transparent,
                              border: Border.all(
                                color: _isShaking
                                    ? Colors.redAccent
                                    : AppColors.primary,
                                width: 2.5,
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 36),

                // Custom Keypad Grid
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKey('1'),
                          _buildKey('2'),
                          _buildKey('3'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKey('4'),
                          _buildKey('5'),
                          _buildKey('6'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKey('7'),
                          _buildKey('8'),
                          _buildKey('9'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildFingerprintButton(),
                          _buildKey('0'),
                          _buildBackspaceButton(),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKey(String label) {
    return GestureDetector(
      onTap: () => _onNumberTap(label),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFingerprintButton() {
    if (!_biometricEnabled) return const SizedBox(width: 68, height: 68);
    return GestureDetector(
      onTap: _triggerBiometricScan,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.fingerprint_rounded,
          color: AppColors.primary,
          size: 30,
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return GestureDetector(
      onTap: _onBackspace,
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(
          Icons.backspace_outlined,
          color: Colors.white70,
          size: 24,
        ),
      ),
    );
  }
}
