import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/premium_card.dart';
import '../auth_providers.dart';
import '../../utils/validators.dart';
import '../../../theme/app_theme.dart';
import '../../../services/app_preferences.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
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
      return;
    }

    final authRepo = ref.read(authRepositoryProvider);
    final user = authRepo.currentUser;
    if (user != null) {
      if (mounted) {
        final pinEnabled = prefs.getBool('security_pin_enabled') ?? false;
        final pinCode = prefs.getString('security_pin_code') ?? '';
        final alreadyUnlocked = prefs.getBool('security_unlocked') ?? false;

        if ((pinEnabled || pinCode.isNotEmpty) && !alreadyUnlocked) {
          context.go('/security-lock');
        } else {
          context.go('/dashboard');
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

  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
      if (!mounted) return;
      context.go('/dashboard');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${error.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [AppColors.scaffoldDark, AppColors.surfaceDark]
                : [AppColors.scaffoldLight, Colors.white],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background circles for premium visual layout
            Positioned(
              top: -size.width * 0.4,
              right: -size.width * 0.3,
              child: Container(
                width: size.width * 0.9,
                height: size.width * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: isDark ? 0.03 : 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: -size.width * 0.3,
              left: -size.width * 0.2,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: isDark ? 0.02 : 0.03),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Clinical Logo
                          Center(
                            child: Container(
                              width: 86,
                              height: 86,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.12),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.08),
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Image.asset(
                                'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.local_hospital_rounded,
                                  color: cs.primary,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Header
                          Text(
                            'GONSTEAD CLINIC',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                              letterSpacing: 1.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            'DOCTOR ACCESS PORTAL',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface.withValues(alpha: 0.6),
                              letterSpacing: 2.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Form card
                          PremiumCard(
                            padding: const EdgeInsets.all(24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Email field
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      hintText: 'Email address',
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                      ),
                                    ),
                                    validator: Validators.email,
                                  ),
                                  const SizedBox(height: 14),

                                  // Password field
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      hintText: 'Password',
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
                                    validator: Validators.password,
                                  ),
                                  const SizedBox(height: 24),

                                  // Sign in button
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _loginWithEmail,
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('Sign In'),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: cs.onSurface.withValues(alpha: 0.12),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'OR',
                                          style: GoogleFonts.poppins(
                                            fontSize: 10.5,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.4,
                                            ),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: cs.onSurface.withValues(alpha: 0.12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  TextButton.icon(
                                    onPressed: () => context.go('/staff-login'),
                                    icon: const Icon(
                                      Icons.badge_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Staff Access Portal'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: cs.primary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
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
