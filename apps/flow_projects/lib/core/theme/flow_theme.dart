import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';

/// Theme mode provider
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Flow color scheme for easy access in widgets
class FlowColorScheme {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color sidebar;
  final Color sidebarSelected;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textPlaceholder;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final bool isDark;

  const FlowColorScheme({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.sidebar,
    required this.sidebarSelected,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textPlaceholder,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.isDark,
  });

  static const light = FlowColorScheme(
    primary: FlowColors.primary,
    primaryLight: FlowColors.primaryLight,
    primaryDark: FlowColors.primaryDark,
    secondary: FlowColors.secondary,
    background: FlowColors.lightBackground,
    surface: FlowColors.lightSurface,
    sidebar: FlowColors.lightSidebar,
    sidebarSelected: FlowColors.lightSidebarSelected,
    border: FlowColors.lightBorder,
    divider: FlowColors.lightDivider,
    textPrimary: FlowColors.lightTextPrimary,
    textSecondary: FlowColors.lightTextSecondary,
    textTertiary: FlowColors.lightTextTertiary,
    textPlaceholder: FlowColors.lightTextPlaceholder,
    success: FlowColors.success,
    warning: FlowColors.warning,
    error: FlowColors.error,
    info: FlowColors.info,
    isDark: false,
  );

  static const dark = FlowColorScheme(
    primary: FlowColors.primary,
    primaryLight: FlowColors.primaryLight,
    primaryDark: FlowColors.primaryDark,
    secondary: FlowColors.secondary,
    background: FlowColors.darkBackground,
    surface: FlowColors.darkSurface,
    sidebar: FlowColors.darkSidebar,
    sidebarSelected: FlowColors.darkSidebarSelected,
    border: FlowColors.darkBorder,
    divider: FlowColors.darkDivider,
    textPrimary: FlowColors.darkTextPrimary,
    textSecondary: FlowColors.darkTextSecondary,
    textTertiary: FlowColors.darkTextTertiary,
    textPlaceholder: FlowColors.darkTextPlaceholder,
    success: FlowColors.success,
    warning: FlowColors.warning,
    error: FlowColors.error,
    info: FlowColors.info,
    isDark: true,
  );
}

/// Extension to access FlowColorScheme from BuildContext
extension FlowThemeExtension on BuildContext {
  FlowColorScheme get flowColors {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark
        ? FlowColorScheme.dark
        : FlowColorScheme.light;
  }
}

/// Main theme configuration
class FlowTheme {
  FlowTheme._();

  static ThemeData light() {
    const colors = FlowColorScheme.light;
    return _buildTheme(colors, Brightness.light);
  }

  static ThemeData dark() {
    const colors = FlowColorScheme.dark;
    return _buildTheme(colors, Brightness.dark);
  }

  static ThemeData _buildTheme(FlowColorScheme colors, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      onPrimary: Colors.white,
      secondary: colors.secondary,
      surface: colors.surface,
      error: colors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      fontFamily: 'Inter',

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),

      // Text theme
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: colors.textPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: colors.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: colors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: colors.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: colors.textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          borderSide: BorderSide(color: colors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FlowSpacing.md,
          vertical: FlowSpacing.sm,
        ),
        hintStyle: TextStyle(color: colors.textPlaceholder),
        labelStyle: TextStyle(color: colors.textSecondary),
      ),

      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpacing.lg,
            vertical: FlowSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.border),
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpacing.lg,
            vertical: FlowSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpacing.md,
            vertical: FlowSpacing.xs,
          ),
        ),
      ),

      // Cards
      cardTheme: CardTheme(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusMd),
          side: BorderSide(color: colors.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),

      // Dialogs
      dialogTheme: DialogTheme(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusMd),
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 0.5,
        space: 0,
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: colors.sidebarSelected,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          color: colors.textSecondary,
        ),
      ),

      // Popup menu
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
        ),
      ),

      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.isDark ? colors.surface : Colors.grey[800],
          borderRadius: BorderRadius.circular(FlowSpacing.radiusXs),
        ),
        textStyle: TextStyle(
          color: colors.isDark ? colors.textPrimary : Colors.white,
          fontSize: 12,
        ),
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.isDark ? colors.surface : Colors.grey[800],
        contentTextStyle: TextStyle(
          color: colors.isDark ? colors.textPrimary : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
