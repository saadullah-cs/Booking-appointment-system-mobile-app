import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import '../../../services/app_preferences.dart';

import '../../shared/widgets/app_shell_scaffold.dart';
import '../../shared/widgets/premium_card.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  String _storedPin = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await AppPreferences.instance.prefs;
    setState(() {
      _pinEnabled = prefs.getBool('security_pin_enabled') ?? false;
      _biometricEnabled = prefs.getBool('security_biometric_enabled') ?? false;
      _storedPin = prefs.getString('security_pin_code') ?? '';
      _isLoading = false;
    });
  }

  Future<void> _togglePinLock(bool value) async {
    if (value) {
      // Prompt to create new PIN
      final newPin = await _showPinDialog(
        title: 'Create 4-Digit PIN',
        description: 'Set a PIN to lock the clinic application.',
      );
      if (newPin == null) return;
      final confirmPin = await _showPinDialog(
        title: 'Confirm 4-Digit PIN',
        description: 'Re-enter your new PIN to confirm.',
      );
      if (confirmPin == null) return;

      if (newPin != confirmPin) {
        _showSnackBar('PINs do not match. Please try again.', isError: true);
        return;
      }

      final prefs = await AppPreferences.instance.prefs;
      await prefs.setBool('security_pin_enabled', true);
      await prefs.setString('security_pin_code', confirmPin);
      setState(() {
        _pinEnabled = true;
        _storedPin = confirmPin;
      });
      _showSnackBar('PIN Lock enabled successfully! 🔒');
    } else {
      // Prompt for current PIN to disable
      final enteredPin = await _showPinDialog(
        title: 'Enter PIN to Disable',
        description: 'Confirm your current PIN code to turn off security lock.',
      );
      if (enteredPin == null) return;

      if (enteredPin != _storedPin) {
        _showSnackBar('Incorrect PIN code.', isError: true);
        return;
      }

      final prefs = await AppPreferences.instance.prefs;
      await prefs.setBool('security_pin_enabled', false);
      await prefs.setBool('security_biometric_enabled', false);
      await prefs.remove('security_pin_code');
      setState(() {
        _pinEnabled = false;
        _biometricEnabled = false;
        _storedPin = '';
      });
      _showSnackBar('PIN Lock disabled.');
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (!_pinEnabled && value) {
      _showSnackBar('Please enable PIN lock first.', isError: true);
      return;
    }

    // Verify device supports biometrics and has enrolled biometrics before enabling.
    final localAuth = LocalAuthentication();
    final canCheck =
        await localAuth.canCheckBiometrics ||
        await localAuth.isDeviceSupported();
    if (value && !canCheck) {
      _showSnackBar(
        'This device does not support biometric authentication.',
        isError: true,
      );
      return;
    }

    if (value) {
      final available = await localAuth.getAvailableBiometrics();
      if (available.isEmpty) {
        _showSnackBar(
          'No biometrics are enrolled on this device. Please enroll a fingerprint or face.',
          isError: true,
        );
        return;
      }
    }

    final prefs = await AppPreferences.instance.prefs;
    await prefs.setBool('security_biometric_enabled', value);
    setState(() {
      _biometricEnabled = value;
    });
    _showSnackBar(
      value
          ? 'Biometric verification enabled. 🧬'
          : 'Biometric verification disabled.',
    );
  }

  Future<void> _changePin() async {
    final oldPin = await _showPinDialog(
      title: 'Enter Current PIN',
      description: 'Verify your current security code.',
    );
    if (oldPin == null) return;

    if (oldPin != _storedPin) {
      _showSnackBar('Incorrect current PIN.', isError: true);
      return;
    }

    final newPin = await _showPinDialog(
      title: 'Enter New PIN',
      description: 'Type your new 4-digit code.',
    );
    if (newPin == null) return;

    final confirmPin = await _showPinDialog(
      title: 'Confirm New PIN',
      description: 'Re-enter your new PIN to save.',
    );
    if (confirmPin == null) return;

    if (newPin != confirmPin) {
      _showSnackBar('PINs do not match.', isError: true);
      return;
    }

    final prefs = await AppPreferences.instance.prefs;
    await prefs.setString('security_pin_code', confirmPin);
    setState(() {
      _storedPin = confirmPin;
    });
    _showSnackBar('PIN code changed successfully! 🔑');
  }

  Future<void> _changeFirebasePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('No authenticated user found.', isError: true);
      return;
    }

    // Step 1: Enter current password to reauthenticate
    final currentPassword = await _showPasswordInputDialog(
      title: 'Verify Current Password',
      description: 'Enter your current account password to continue.',
    );
    if (currentPassword == null || currentPassword.isEmpty) return;

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email ?? '',
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _showSnackBar(
        e.code == 'wrong-password'
            ? 'Incorrect current password. Please try again.'
            : 'Authentication failed: ${e.message}',
        isError: true,
      );
      return;
    } catch (_) {
      _showSnackBar('Authentication failed. Please try again.', isError: true);
      return;
    }

    // Step 2: Enter new password
    final newPassword = await _showPasswordInputDialog(
      title: 'Enter New Password',
      description: 'Minimum 6 characters. Use a strong password.',
    );
    if (newPassword == null || newPassword.isEmpty) return;

    if (newPassword.length < 6) {
      _showSnackBar('Password must be at least 6 characters.', isError: true);
      return;
    }

    // Step 3: Confirm new password
    final confirmPassword = await _showPasswordInputDialog(
      title: 'Confirm New Password',
      description: 'Re-enter your new password to confirm.',
    );
    if (confirmPassword == null || confirmPassword.isEmpty) return;

    if (newPassword != confirmPassword) {
      _showSnackBar('Passwords do not match.', isError: true);
      return;
    }

    try {
      await user.updatePassword(newPassword);
      _showSnackBar('Account password changed successfully! 🔐');
    } on FirebaseAuthException catch (e) {
      _showSnackBar('Failed to update password: ${e.message}', isError: true);
    } catch (e) {
      _showSnackBar('Unexpected error: $e', isError: true);
    }
  }

  Future<String?> _showPasswordInputDialog({
    required String title,
    required String description,
  }) async {
    final controller = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  style: GoogleFonts.poppins(),
                  decoration: InputDecoration(
                    hintText: 'Enter password',
                    hintStyle: GoogleFonts.poppins(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setS(() => obscure = !obscure),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: Text(
                  'Continue',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    final primaryColor = Theme.of(context).colorScheme.primary;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.redAccent : primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _showPinDialog({
    required String title,
    required String description,
  }) async {
    String input = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            return Dialog(
              backgroundColor: Colors.transparent,
              child: PremiumCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.65),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final filled = index < input.length;
                        return Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? cs.primary : Colors.transparent,
                            border: Border.all(color: cs.primary, width: 2),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 28),
                    // Dialog Numpad grid
                    SizedBox(
                      width: 200,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, i) {
                          if (i == 9) {
                            return IconButton(
                              icon: const Icon(
                                Icons.cancel_outlined,
                                color: Colors.grey,
                              ),
                              onPressed: () => Navigator.pop(context),
                            );
                          }
                          if (i == 11) {
                            return IconButton(
                              icon: const Icon(
                                Icons.backspace_outlined,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                if (input.isNotEmpty) {
                                  setDialogState(
                                    () => input = input.substring(
                                      0,
                                      input.length - 1,
                                    ),
                                  );
                                }
                              },
                            );
                          }
                          final digit = i == 10 ? '0' : (i + 1).toString();
                          return GestureDetector(
                            onTap: () {
                              if (input.length < 4) {
                                setDialogState(() => input += digit);
                                if (input.length == 4) {
                                  Future.delayed(
                                    const Duration(milliseconds: 150),
                                    () {
                                      if (context.mounted) {
                                        Navigator.pop(context, input);
                                      }
                                    },
                                  );
                                }
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                digit,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      title: 'Security Settings',
      currentRoute: '/profile',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PremiumCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.security_rounded,
                          color: cs.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App Security Locks',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'Restrict access to patients, scheduling, and billing records.',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'SECURITY OPTIONS',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                PremiumCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: _pinEnabled,
                          onChanged: _togglePinLock,
                          title: Text(
                            'PIN Lock Protection',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'Require a 4-digit code to open the application',
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.pin_rounded,
                              color: cs.primary,
                              size: 20,
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile.adaptive(
                          value: _biometricEnabled,
                          onChanged: _pinEnabled ? _toggleBiometrics : null,
                          title: Text(
                            'Biometric Fingerprint',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'Verify your identity using fingerprint scanner',
                            style: GoogleFonts.poppins(fontSize: 12),
                          ),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (_pinEnabled ? cs.primary : Colors.grey)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.fingerprint_rounded,
                              color: _pinEnabled ? cs.primary : Colors.grey,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_pinEnabled) ...[
                  const SizedBox(height: 20),
                  Text(
                    'CREDENTIAL MANAGEMENT',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PremiumCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.lock_reset_rounded,
                          color: cs.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Change Security PIN',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        'Update your active 4-digit code',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _changePin,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'ACCOUNT SECURITY',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                PremiumCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.key_rounded,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Change Account Password',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Update your Firebase / Google account login password',
                      style: GoogleFonts.poppins(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changeFirebasePassword,
                  ),
                ),
              ],
            ),
    );
  }
}
