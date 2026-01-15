import 'package:flutter/material.dart';

/// Bear-inspired color palette
/// Primary accent: Warm red-orange (Bear's signature)
/// Secondary: Soft neutrals with depth
class FlowColors {
  // === PRIMARY (Bear's signature red-orange) ===
  static const Color primary = Color(0xFFDA4453);
  static const Color primaryLight = Color(0xFFED5565);
  static const Color primaryDark = Color(0xFFC43D4B);

  // === LIGHT THEME ===
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF5F5F5);

  // Sidebar (slightly darker, like Bear)
  static const Color lightSidebar = Color(0xFFF0F0F0);
  static const Color lightSidebarSelected = Color(0xFFE8E8E8);

  // Text hierarchy
  static const Color lightTextPrimary = Color(0xFF2C2C2E);
  static const Color lightTextSecondary = Color(0xFF636366);
  static const Color lightTextTertiary = Color(0xFF8E8E93);
  static const Color lightTextPlaceholder = Color(0xFFAEAEB2);

  // Borders & dividers (very subtle)
  static const Color lightDivider = Color(0xFFE5E5EA);
  static const Color lightBorder = Color(0xFFD1D1D6);

  // === DARK THEME (Bear's "Charcoal" inspired) ===
  static const Color darkBackground = Color(0xFF1C1C1E);
  static const Color darkSurface = Color(0xFF2C2C2E);
  static const Color darkSurfaceVariant = Color(0xFF3A3A3C);

  // Sidebar
  static const Color darkSidebar = Color(0xFF252527);
  static const Color darkSidebarSelected = Color(0xFF3A3A3C);

  // Text hierarchy
  static const Color darkTextPrimary = Color(0xFFF2F2F7);
  static const Color darkTextSecondary = Color(0xFFAEAEB2);
  static const Color darkTextTertiary = Color(0xFF636366);
  static const Color darkTextPlaceholder = Color(0xFF48484A);

  // Borders & dividers
  static const Color darkDivider = Color(0xFF38383A);
  static const Color darkBorder = Color(0xFF48484A);

  // === SEMANTIC COLORS ===
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFCC00);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);

  // Priority colors (subtle, not harsh)
  static const Color priorityUrgent = Color(0xFFFF6B6B);
  static const Color priorityHigh = Color(0xFFFFAB4A);
  static const Color priorityMedium = Color(0xFFFFD93D);
  static const Color priorityLow = Color(0xFF6BCB77);

  // === SPECIAL EFFECTS ===
  // Glassmorphism (for iOS 26+ Liquid Glass style)
  static const Color glassLight = Color(0x80FFFFFF);
  static const Color glassDark = Color(0x40000000);
  static const double glassBlur = 20.0;

  // Shadows (very soft, Bear-style)
  static const List<BoxShadow> cardShadowLight = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> cardShadowDark = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  // Get priority color
  static Color getPriorityColor(int priority) {
    switch (priority) {
      case 4:
        return priorityUrgent;
      case 3:
        return priorityHigh;
      case 2:
        return priorityMedium;
      case 1:
        return priorityLow;
      default:
        return Colors.transparent;
    }
  }
}
