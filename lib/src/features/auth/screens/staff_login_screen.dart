import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/premium_card.dart';
import '../../../services/app_preferences.dart';
import '../../../services/staff_activity_logger.dart';
import '../../../theme/app_theme.dart';
import '../auth_providers.dart';

class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await AppPreferences.instance.prefs;
    final isStaffLoggedIn = prefs.getBool('is_staff_logged_in') ?? false;
    if (isStaffLoggedIn) {
      if (mounted) {
        final staffEmail = prefs.getString('logged_in_staff_email') ?? '';
        final staffPinEnabled =
            prefs.getBool('staff_pin_enabled_$staffEmail') ?? false;
        final staffPinCode =
            prefs.getString('staff_pin_code_$staffEmail') ?? '';
        final staffUnlocked =
            prefs.getBool('staff_unlocked_$staffEmail') ?? false;

        if ((staffPinEnabled || staffPinCode.isNotEmpty) && !staffUnlocked) {
          context.go('/staff-lock');
        } else {
          context.go('/staff-dashboard');
        }
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _login() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final staffList = await authRepo.loadStaffCredentials();

      final match = staffList.firstWhere(
        (s) => s['email'] == email && s['password'] == password,
        orElse: () => {},
      );

      if (match.isNotEmpty) {
        // Successful login
        final prefs = await AppPreferences.instance.prefs;
        await prefs.setBool('is_staff_logged_in', true);
        await prefs.setString('logged_in_staff_email', email);
        await prefs.setString(
          'offline_password_$email',
          password,
        ); // cache offline password

        final staffPinEnabled =
            prefs.getBool('staff_pin_enabled_$email') ?? false;

        // Log staff login activity
        await StaffActivityLogger().logActivity(
          staffEmail: email,
          action: 'Login',
          featureUsed: 'Staff Login Screen',
        );

        _showSnackBar('Welcome to the Staff Portal! 🎉');
        if (!mounted) return;
        if (staffPinEnabled) {
          context.go('/staff-lock');
        } else {
          context.go('/staff-dashboard');
        }
      } else {
        // Check offline cache as fallback
        final prefs = await AppPreferences.instance.prefs;
        final cachedPassword = prefs.getString('offline_password_$email');
        if (cachedPassword != null && cachedPassword == password) {
          await prefs.setBool('is_staff_logged_in', true);
          await prefs.setString('logged_in_staff_email', email);

          final staffPinEnabled =
              prefs.getBool('staff_pin_enabled_$email') ?? false;

          _showSnackBar('Logged in via offline cache.');
          if (!mounted) return;
          if (staffPinEnabled) {
            context.go('/staff-lock');
          } else {
            context.go('/staff-dashboard');
          }
        } else {
          _showSnackBar(
            'Invalid email or password. Please verify with doctor.',
            isError: true,
          );
        }
      }
    } catch (e) {
      _showSnackBar('Login failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF020617), // Deep midnight blue
                    const Color(0xFF0F172A), // Dark slate
                    const Color(0xFF1E293B), // Medium slate
                  ]
                : [
                    const Color(0xFFF1F5F9), // Light Slate 100
                    const Color(0xFFE2E8F0), // Light Slate 200
                    Colors.white,
                  ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative backdrop design glows
            Positioned(
              top: -size.width * 0.4,
              left: -size.width * 0.2,
              child: Container(
                width: size.width * 0.9,
                height: size.width * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -size.width * 0.3,
              right: -size.width * 0.2,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(
                    alpha: isDark ? 0.08 : 0.05,
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // App Branding
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : cs.primary.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Image.asset(
                              'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
                              width: 60,
                              height: 60,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.badge_rounded,
                                color: cs.primary,
                                size: 50,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'GONSTEAD CLINIC',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'STAFF ACCESS PORTAL',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface.withValues(alpha: 0.6),
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Premium Form Card
                          PremiumCard(
                            padding: const EdgeInsets.all(28),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Access Login',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Enter credentials assigned by your Clinic Administrator.',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),

                                  // Email Field
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Staff Email',
                                      prefixIcon: Icon(Icons.email_outlined),
                                      hintText: 'receptionist@gct.com',
                                    ),
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) {
                                        return 'Email is required';
                                      }
                                      if (!val.contains('@')) {
                                        return 'Enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 18),

                                  // Password Field
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      labelText: 'Access Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                      ),
                                    ),
                                    validator: (val) {
                                      if (val == null || val.isEmpty) {
                                        return 'Password is required';
                                      }
                                      if (val.length < 6) {
                                        return 'Must be at least 6 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 28),

                                  // Submit button
                                  _isLoading
                                      ? Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation(
                                              cs.primary,
                                            ),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed: _login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: cs.primary,
                                            foregroundColor: cs.onPrimary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            elevation: 8,
                                            shadowColor: cs.primary.withValues(
                                              alpha: 0.3,
                                            ),
                                          ),
                                          child: Text(
                                            'Sign In as Staff',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Back button
                          TextButton.icon(
                            onPressed: () => context.go('/login'),
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: cs.onSurface.withValues(alpha: 0.7),
                              size: 16,
                            ),
                            label: Text(
                              'Return to Doctor Portal',
                              style: GoogleFonts.poppins(
                                color: cs.onSurface.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
