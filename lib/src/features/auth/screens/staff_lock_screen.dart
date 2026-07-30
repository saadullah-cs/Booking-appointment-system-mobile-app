import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../services/app_preferences.dart';
import '../../../theme/app_theme.dart';

class StaffLockScreen extends ConsumerStatefulWidget {
  const StaffLockScreen({super.key});

  @override
  ConsumerState<StaffLockScreen> createState() => _StaffLockScreenState();
}

class _StaffLockScreenState extends ConsumerState<StaffLockScreen>
    with TickerProviderStateMixin {
  String _enteredPin = '';
  String _storedPin = '';
  String _staffEmail = '';
  bool _isShaking = false;
  bool _isLoading = true;

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
    final staffEmail = prefs.getString('logged_in_staff_email') ?? '';
    final storedPin = prefs.getString('staff_pin_code_$staffEmail') ?? '';

    setState(() {
      _staffEmail = staffEmail;
      _storedPin = storedPin;
      _isLoading = false;
    });
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
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          context.go('/staff-dashboard');
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

  Future<void> _logout() async {
    final prefs = await AppPreferences.instance.prefs;
    await prefs.remove('is_staff_logged_in');
    await prefs.remove('logged_in_staff_email');
    if (mounted) {
      context.go('/staff-login');
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
    final displayName = _staffEmail.isNotEmpty
        ? _staffEmail.split('@')[0].toUpperCase()
        : 'STAFF MEMBER';

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
                const SizedBox(height: 20),

                // Staff Access Avatar/Icon
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
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
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.badge_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),

                // Title Display
                Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter 4-Digit PIN to unlock',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 36),

                // PIN Indicators
                AnimatedBuilder(
                  animation: _shakeController,
                  builder: (context, child) {
                    final double offset = _isShaking
                        ? (12 *
                              (1.0 - _shakeAnim.value) *
                              (identityHashCode(this) % 2 == 0 ? 1 : -1))
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

                const SizedBox(height: 48),

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
                          const SizedBox(width: 68, height: 68), // Spacer
                          _buildKey('0'),
                          _buildBackspaceButton(),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Return/Logout option
                TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Colors.white60,
                    size: 16,
                  ),
                  label: Text(
                    'Logout / Switch Account',
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
