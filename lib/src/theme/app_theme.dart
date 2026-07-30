import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary brand palette
  static const Color primary = Color(0xFF0E7490);
  static const Color primaryDark = Color(0xFF0891B2);
  static const Color accent = Color(0xFF06B6D4);
  static const Color accentDark = Color(0xFF0891B2);

  // Surface colours
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color scaffoldLight = Color(0xFFF8FAFC);
  static const Color scaffoldDark = Color(0xFF0F172A);

  // Status tokens
  static const Color statusConfirmed = Color(0xFF00A86B);
  static const Color statusConfirmedBg = Color(0xFFE6F7F1);
  static const Color statusPending = Color(0xFFF59E0B);
  static const Color statusPendingBg = Color(0xFFFFFBEB);
  static const Color statusCancelled = Color(0xFFEF4444);
  static const Color statusCancelledBg = Color(0xFFFEE2E2);
  static const Color statusCompleted = Color(0xFF3B82F6);
  static const Color statusCompletedBg = Color(0xFFEFF6FF);

  // Gradient sets
  static const List<Color> heroGradient = [
    Color(0xFF0E7490),
    Color(0xFF06B6D4),
  ];
  static const List<Color> heroGradientDark = [
    Color(0xFF0F172A),
    Color(0xFF1E293B),
  ];
  static const List<Color> cardGradient = [
    Color(0xFF0F172A),
    Color(0xFF0E7490),
  ];

  // Neutral
  static const Color navy = Color(0xFF0F172A);
  static const Color navyLight = Color(0xFF334155);
  static const Color grey50 = Color(0xFFF8FAFC);
  static const Color grey100 = Color(0xFFF1F5F9);
  static const Color grey200 = Color(0xFFE2E8F0);
  static const Color grey400 = Color(0xFF94A3B8);
  static const Color grey600 = Color(0xFF475569);
}

Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'confirmed':
      return AppColors.statusConfirmed;
    case 'cancelled':
      return AppColors.statusCancelled;
    case 'completed':
      return AppColors.statusCompleted;
    case 'no show':
      return const Color(0xFF8B5CF6);
    default:
      return AppColors.statusPending;
  }
}

Color statusBgColor(String status) {
  switch (status.toLowerCase()) {
    case 'confirmed':
      return AppColors.statusConfirmedBg;
    case 'cancelled':
      return AppColors.statusCancelledBg;
    case 'completed':
      return AppColors.statusCompletedBg;
    case 'no show':
      return const Color(0xFFF3E8FF);
    default:
      return AppColors.statusPendingBg;
  }
}

class AppTheme {
  static TextTheme _buildTextTheme(ColorScheme colorScheme) {
    final base = GoogleFonts.poppinsTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 15,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: colorScheme.onSurface.withValues(alpha: 0.75),
        fontSize: 13,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: colorScheme.onSurface.withValues(alpha: 0.55),
        fontSize: 12,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }

  static ColorScheme _buildLightScheme() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      tertiary: const Color(0xFF6366F1),
      surface: AppColors.surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AppColors.navy,
      error: AppColors.statusCancelled,
    );
  }

  static ColorScheme _buildDarkScheme() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: const Color(0xFF60A5FA),
      secondary: const Color(0xFF34D399),
      tertiary: const Color(0xFFA78BFA),
      surface: AppColors.surfaceDark,
      onPrimary: const Color(0xFF070F1C),
      onSecondary: const Color(0xFF070F1C),
      onSurface: const Color(0xFFEDF2FF),
      error: const Color(0xFFFCA5A5),
    );
  }

  static ThemeData _buildBaseTheme(
    ColorScheme colorScheme, {
    required bool isDark,
  }) {
    final textTheme = _buildTextTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark
          ? AppColors.scaffoldDark
          : AppColors.scaffoldLight,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        elevation: isDark ? 8 : 4,
        shadowColor: isDark
            ? Colors.black.withValues(alpha: 0.4)
            : AppColors.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A2A40) : AppColors.grey100,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : AppColors.grey200,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.poppins(
          color: colorScheme.onSurface.withValues(alpha: 0.45),
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.poppins(
          color: colorScheme.onSurface.withValues(alpha: 0.6),
          fontSize: 14,
        ),
        prefixIconColor: colorScheme.onSurface.withValues(alpha: 0.5),
        suffixIconColor: colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : AppColors.grey200,
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.6),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.55),
            size: 24,
          );
        }),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isDark ? const Color(0xFF1E3A5F) : AppColors.navy,
        contentTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 13,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        titleTextStyle: GoogleFonts.poppins(
          color: isDark ? Colors.white : AppColors.navy,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static final ThemeData lightTheme = _buildBaseTheme(
    _buildLightScheme(),
    isDark: false,
  );
  static final ThemeData darkTheme = _buildBaseTheme(
    _buildDarkScheme(),
    isDark: true,
  );
}
