import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/app_preferences.dart';
import '../../../theme/app_theme.dart';

class SplashEntryScreen extends StatefulWidget {
  const SplashEntryScreen({super.key});

  @override
  State<SplashEntryScreen> createState() => _SplashEntryScreenState();
}

class _SplashEntryScreenState extends State<SplashEntryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _scaleController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
    _scaleController.forward();

    // Auto-navigate after a short startup delay
    _timer = Timer(const Duration(milliseconds: 500), () {
      _handleRedirect();
    });
  }

  Future<void> _handleRedirect() async {
    final prefs = await AppPreferences.instance.prefs;
    // Reset unlock status on cold boot so security screen always shows
    await prefs.setBool('security_unlocked', false);

    final isStaffLoggedIn = prefs.getBool('is_staff_logged_in') ?? false;
    if (isStaffLoggedIn) {
      if (mounted) {
        final staffEmail = prefs.getString('logged_in_staff_email') ?? '';
        final staffPinEnabled =
            prefs.getBool('staff_pin_enabled_$staffEmail') ?? false;
        if (staffPinEnabled) {
          context.go('/staff-lock');
        } else {
          context.go('/staff-dashboard');
        }
      }
      return;
    }

    bool firebaseSignedIn = false;
    try {
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null) {
        try {
          await FirebaseAuth.instance.currentUser!.reload();
          firebaseSignedIn = FirebaseAuth.instance.currentUser != null;
        } on FirebaseAuthException catch (e) {
          debugPrint('Firebase session validation failed: ${e.code}');
          if (e.code == 'user-not-found' ||
              e.code == 'user-disabled' ||
              e.code == 'invalid-credential') {
            await FirebaseAuth.instance.signOut();
            final prefs = await AppPreferences.instance.prefs;
            await prefs.remove('local_auth_current_user');
            if (mounted) context.go('/login');
            return;
          }
        }
      }
    } catch (_) {
      firebaseSignedIn = false;
    }

    final storedUser = prefs.getString('local_auth_current_user');
    final pinEnabled = prefs.getBool('security_pin_enabled') ?? false;
    final alreadyUnlocked = prefs.getBool('security_unlocked') ?? false;
    final hasLocalUser = storedUser != null && storedUser.isNotEmpty;

    if (!mounted) return;
    if (!firebaseSignedIn && !hasLocalUser) {
      context.go('/login');
    } else if (pinEnabled && !alreadyUnlocked) {
      context.go('/security-lock');
    } else {
      context.go('/dashboard');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF09315D), // Dark Blue
              Color(0xFF1E5B7E), // Medium Teal-Blue
              AppColors.primary, // GCT Teal
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background circles
            Positioned(
              top: -size.width * 0.4,
              right: -size.width * 0.3,
              child: Container(
                width: size.width * 0.9,
                height: size.width * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: -size.width * 0.2,
              left: -size.width * 0.2,
              child: Container(
                width: size.width * 0.8,
                height: size.width * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),

            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Clinic Logo / Icon
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 25,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              'assets/ChatGPT Image Jul 9, 2025, 11_09_56 PM.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.local_hospital_rounded,
                                color: AppColors.primary,
                                size: 50,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Clinic Branding
                          Text(
                            'GONSTEAD CHIROPRACTIC TREATMENT',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Precision Spine & Posture Correction',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Clinical details card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow(
                                  icon: Icons.person_rounded,
                                  title: 'Attending Practitioner',
                                  value:
                                      'DR. BASHIR AHMAD\nChiropractic Specialist',
                                ),
                                const Divider(
                                  color: Colors.white24,
                                  height: 24,
                                ),
                                _buildDetailRow(
                                  icon: Icons.access_time_rounded,
                                  title: 'Clinic Timings',
                                  value:
                                      'Mon – Sat: 08:00 AM – 06:00 PM\nSunday: CLOSED / WEEKLY OFF',
                                ),
                                const Divider(
                                  color: Colors.white24,
                                  height: 24,
                                ),
                                _buildDetailRow(
                                  icon: Icons.location_on_rounded,
                                  title: 'Clinic Location',
                                  value:
                                      'Tehsil Road, Near Peshawar Model School, Nowshera City, KPK.',
                                ),
                                const Divider(
                                  color: Colors.white24,
                                  height: 24,
                                ),
                                _buildDetailRow(
                                  icon: Icons.phone_android_rounded,
                                  title: 'Emergency Contact',
                                  value: '+92 304 6996267',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Progress loader & CTA
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'Loading system...',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () {
                              _timer?.cancel();
                              _handleRedirect();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Proceed',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                              ],
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

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
