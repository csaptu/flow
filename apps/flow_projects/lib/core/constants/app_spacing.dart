import 'package:flutter/material.dart';

/// Consistent spacing system for Flow Projects
class FlowSpacing {
  FlowSpacing._();

  // Base unit (4px)
  static const double unit = 4.0;

  // Spacing scale
  static const double xxs = 4.0;   // 1 unit
  static const double xs = 8.0;    // 2 units
  static const double sm = 12.0;   // 3 units
  static const double md = 16.0;   // 4 units
  static const double lg = 24.0;   // 6 units
  static const double xl = 32.0;   // 8 units
  static const double xxl = 48.0;  // 12 units

  // Border radius
  static const double radiusXs = 4.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;

  // Layout dimensions
  static const double sidebarWidth = 240.0;
  static const double sidebarCollapsedWidth = 72.0;
  static const double contentMaxWidth = 1200.0;
  static const double ganttRowHeight = 48.0;
  static const double ganttHeaderHeight = 56.0;
  static const double wbsNodeHeight = 44.0;
  static const double wbsIndent = 24.0;

  // Common paddings
  static const EdgeInsets screenPadding = EdgeInsets.all(md);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );
  static const EdgeInsets wbsNodePadding = EdgeInsets.symmetric(
    horizontal: sm,
    vertical: xs,
  );
}
