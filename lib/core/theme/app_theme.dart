import 'package:flutter/material.dart';

/// Central design system: color roles, type scale, shapes, and component
/// themes. Screens should pull from here (AppTheme.light, AppRadius,
/// AppSpacing, AppGradients, StatusColors) rather than hardcoding values,
/// so the look stays consistent as new screens get added.
class AppTheme {
  AppTheme._();

  static const String fontFamily = 'PlusJakartaSans';

  // Brand palette — matched against the PFMSD Enterprise Design System
  // reference boards: a near-black deep navy for headers/splash/hero
  // surfaces, gold for the brand accent (FAB, badges, highlights), and a
  // vibrant royal-blue for icon tiles distinct from the darker navy.
  static const Color navyDarkest = Color(0xFF061F4A);
  static const Color navyDark = Color(0xFF082B63);
  static const Color navy = Color(0xFF0B3578);
  static const Color accentBlue = Color(0xFF1E5BB8);
  static const Color gold = Color(0xFFF2B705);
  static const Color success = Color(0xFF27AE60);
  static const Color plum = Color(0xFFB84FE0);
  static const Color ink = Color(0xFF14213D);
  static const Color mist = Color(0xFFF5F8FC);

  static ColorScheme get _colorScheme =>
      ColorScheme.fromSeed(
        seedColor: navy,
        brightness: Brightness.light,
      ).copyWith(
        primary: navy,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE6EFFB),
        onPrimaryContainer: navyDark,
        secondary: gold,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFFFF3C9),
        onSecondaryContainer: const Color(0xFF6B4E0A),
        tertiary: accentBlue,
        onTertiary: Colors.white,
        surface: Colors.white,
        onSurface: ink,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF4F7FB),
        surfaceContainer: const Color(0xFFEEF3F9),
        surfaceContainerHigh: const Color(0xFFE4EBF4),
        surfaceContainerHighest: const Color(0xFFD9E3EF),
        outline: const Color(0xFFC6D5E6),
        outlineVariant: const Color(0xFFE9EFF6),
        error: const Color(0xFFBA1A1A),
      );

  static TextTheme _textTheme(ColorScheme scheme) {
    TextStyle base(
      double size,
      FontWeight weight, {
      double? letterSpacing,
      double? height,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing ?? 0,
        height: height,
        color: color ?? scheme.onSurface,
      );
    }

    return TextTheme(
      displaySmall: base(
        34,
        FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      headlineMedium: base(
        26,
        FontWeight.w800,
        letterSpacing: -0.4,
        height: 1.2,
      ),
      headlineSmall: base(
        22,
        FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25,
      ),
      titleLarge: base(19, FontWeight.w700, letterSpacing: -0.2, height: 1.3),
      titleMedium: base(16, FontWeight.w600, height: 1.35),
      titleSmall: base(14, FontWeight.w600, height: 1.3),
      bodyLarge: base(16, FontWeight.w400, height: 1.5),
      bodyMedium: base(14, FontWeight.w400, height: 1.5),
      bodySmall: base(
        12.5,
        FontWeight.w500,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: base(14, FontWeight.w700, letterSpacing: 0.1),
      labelMedium: base(12, FontWeight.w700, letterSpacing: 0.2),
      labelSmall: base(11, FontWeight.w700, letterSpacing: 0.3),
    );
  }

  static ThemeData get light {
    final scheme = _colorScheme;
    final textTheme = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mist,
      fontFamily: fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        backgroundColor: mist,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 58,
        scrolledUnderElevation: 3,
        shadowColor: ink.withValues(alpha: 0.08),
        centerTitle: false,
        titleTextStyle: textTheme.titleSmall?.copyWith(
          color: navyDark,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: const IconThemeData(color: navyDark, size: 21),
        actionsIconTheme: const IconThemeData(color: navyDark, size: 21),
      ),

      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: ink.withValues(alpha: 0.10),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: textTheme.bodySmall,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          shadowColor: ink.withValues(alpha: 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          elevation: 1,
          shadowColor: ink.withValues(alpha: 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        elevation: 4,
        shadowColor: ink.withValues(alpha: 0.10),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        highlightElevation: 5,
        extendedTextStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
      ),
    );
  }
}

/// Consistent corner radii across the app — matches the design's soft,
/// rounded, "friendly government service" feel rather than sharp Material
/// defaults.
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

/// 4pt-based spacing scale used in place of magic numbers in padding/gaps.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Gradients for hero/accent surfaces (login background, headers).
class AppGradients {
  AppGradients._();

  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppTheme.navyDarkest, AppTheme.navy, AppTheme.accentBlue],
  );

  static const LinearGradient goldAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE9B94A), AppTheme.gold],
  );
}

/// Soft, low-opacity shadow used for elevated "premium" cards where the
/// default Material elevation reads as flat.
List<BoxShadow> softShadow({double opacity = 0.06}) => [
  BoxShadow(
    color: AppTheme.ink.withValues(alpha: opacity),
    blurRadius: 16,
    offset: const Offset(0, 4),
    spreadRadius: -4,
  ),
];

/// Maps ticket priority/status to a consistent color across screens.
class StatusColors {
  StatusColors._();

  static const Color critical = Color(0xFFC0392B);
  static const Color high = Color(0xFFE08E45);
  static const Color medium = Color(0xFFF5A623);
  static const Color low = Color(0xFF27AE60);

  static const Color open = Color(0xFF2B6CB0);
  static const Color assigned = Color(0xFF6B4FA0);
  static const Color inProgress = Color(0xFFF5A623);
  static const Color escalated = Color(0xFFC0392B);
  static const Color resolved = Color(0xFF27AE60);
  static const Color reopened = Color(0xFFC0392B);
  static const Color closed = Color(0xFF6B7A8C);
}
