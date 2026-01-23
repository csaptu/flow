import 'package:flutter/material.dart';

/// Bear-inspired spacing
/// - Generous whitespace
/// - Consistent rhythm
/// - Breathable layouts
class FlowSpacing {
  // Base unit (4px grid)
  static const double unit = 4.0;

  // Spacing scale
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // Component-specific
  static const double sidebarWidth = 280.0;
  static const double sidebarCollapsedWidth = 72.0;
  static const double taskListMaxWidth = 720.0;
  static const double taskItemHeight = 56.0;
  static const double taskItemPaddingH = 16.0;
  static const double taskItemPaddingV = 12.0;
  static const double dialogMaxWidth = 420.0;

  // Border radius (soft, Bear-style)
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 999.0;

  // Content padding
  static const EdgeInsets screenPadding = EdgeInsets.all(24.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 12.0,
  );
}
