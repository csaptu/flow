import 'package:flutter/material.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';

class FlowTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: FlowColors.primary,
        onPrimary: Colors.white,
        surface: FlowColors.lightSurface,
        onSurface: FlowColors.lightTextPrimary,
        error: FlowColors.error,
      ),
      scaffoldBackgroundColor: FlowColors.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: FlowColors.lightSurface,
        foregroundColor: FlowColors.lightTextPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: FlowColors.lightTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: FlowColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FlowColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: const BorderSide(color: FlowColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: FlowColors.lightDivider,
        thickness: 0.5,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return FlowColors.primary;
          }
          return Colors.transparent;
        }),
        shape: const CircleBorder(),
        side: const BorderSide(color: FlowColors.lightBorder, width: 1.5),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.35,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.6,
          letterSpacing: 0.1,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.6,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
      extensions: [
        FlowColorScheme.light(),
      ],
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: FlowColors.primary,
        onPrimary: Colors.white,
        surface: FlowColors.darkSurface,
        onSurface: FlowColors.darkTextPrimary,
        error: FlowColors.error,
      ),
      scaffoldBackgroundColor: FlowColors.darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: FlowColors.darkSurface,
        foregroundColor: FlowColors.darkTextPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: FlowColors.darkTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: FlowColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FlowColors.darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: const BorderSide(color: FlowColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: FlowColors.darkDivider,
        thickness: 0.5,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return FlowColors.primary;
          }
          return Colors.transparent;
        }),
        shape: const CircleBorder(),
        side: const BorderSide(color: FlowColors.darkBorder, width: 1.5),
      ),
      extensions: [
        FlowColorScheme.dark(),
      ],
    );
  }
}

/// Theme extension for custom colors
class FlowColorScheme extends ThemeExtension<FlowColorScheme> {
  final Color primary;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color sidebar;
  final Color sidebarSelected;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color divider;
  final Color border;
  final Color error;
  final Color warning;
  final Color success;

  FlowColorScheme({
    required this.primary,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.sidebar,
    required this.sidebarSelected,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textPlaceholder,
    required this.divider,
    required this.border,
    required this.error,
    required this.warning,
    required this.success,
  });

  factory FlowColorScheme.light() => FlowColorScheme(
        primary: FlowColors.primary,
        background: FlowColors.lightBackground,
        surface: FlowColors.lightSurface,
        surfaceVariant: FlowColors.lightSurfaceVariant,
        sidebar: FlowColors.lightSidebar,
        sidebarSelected: FlowColors.lightSidebarSelected,
        textPrimary: FlowColors.lightTextPrimary,
        textSecondary: FlowColors.lightTextSecondary,
        textTertiary: FlowColors.lightTextTertiary,
        textPlaceholder: FlowColors.lightTextPlaceholder,
        divider: FlowColors.lightDivider,
        border: FlowColors.lightBorder,
        error: FlowColors.error,
        warning: FlowColors.warning,
        success: FlowColors.success,
      );

  factory FlowColorScheme.dark() => FlowColorScheme(
        primary: FlowColors.primary,
        background: FlowColors.darkBackground,
        surface: FlowColors.darkSurface,
        surfaceVariant: FlowColors.darkSurfaceVariant,
        sidebar: FlowColors.darkSidebar,
        sidebarSelected: FlowColors.darkSidebarSelected,
        textPrimary: FlowColors.darkTextPrimary,
        textSecondary: FlowColors.darkTextSecondary,
        textTertiary: FlowColors.darkTextTertiary,
        textPlaceholder: FlowColors.darkTextPlaceholder,
        divider: FlowColors.darkDivider,
        border: FlowColors.darkBorder,
        error: FlowColors.error,
        warning: FlowColors.warning,
        success: FlowColors.success,
      );

  @override
  ThemeExtension<FlowColorScheme> copyWith({
    Color? primary,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? sidebar,
    Color? sidebarSelected,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textPlaceholder,
    Color? divider,
    Color? border,
    Color? error,
    Color? warning,
    Color? success,
  }) {
    return FlowColorScheme(
      primary: primary ?? this.primary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      sidebar: sidebar ?? this.sidebar,
      sidebarSelected: sidebarSelected ?? this.sidebarSelected,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textPlaceholder: textPlaceholder ?? this.textPlaceholder,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      success: success ?? this.success,
    );
  }

  @override
  ThemeExtension<FlowColorScheme> lerp(
    covariant ThemeExtension<FlowColorScheme>? other,
    double t,
  ) {
    if (other is! FlowColorScheme) return this;
    return FlowColorScheme(
      primary: Color.lerp(primary, other.primary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarSelected: Color.lerp(sidebarSelected, other.sidebarSelected, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textPlaceholder: Color.lerp(textPlaceholder, other.textPlaceholder, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

extension FlowColorSchemeExtension on BuildContext {
  FlowColorScheme get flowColors =>
      Theme.of(this).extension<FlowColorScheme>() ?? FlowColorScheme.light();
}
