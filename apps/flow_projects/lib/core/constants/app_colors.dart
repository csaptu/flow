import 'package:flutter/material.dart';

/// Flow Projects color system - Bear App inspired
/// Same design language as Flow Tasks for consistency
class FlowColors {
  FlowColors._();

  // Primary brand color - Bear's signature red-orange
  static const Color primary = Color(0xFFDA4453);
  static const Color primaryLight = Color(0xFFE8606D);
  static const Color primaryDark = Color(0xFFC13A48);

  // Secondary accent - Warm orange for projects
  static const Color secondary = Color(0xFFFF9500);
  static const Color secondaryLight = Color(0xFFFFAA33);
  static const Color secondaryDark = Color(0xFFE68600);

  // Status colors
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF007AFF);

  // Light theme colors
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSidebar = Color(0xFFF5F5F5);
  static const Color lightSidebarSelected = Color(0xFFFFECED);
  static const Color lightBorder = Color(0xFFE5E5E5);
  static const Color lightDivider = Color(0xFFEEEEEE);

  static const Color lightTextPrimary = Color(0xFF1C1C1E);
  static const Color lightTextSecondary = Color(0xFF636366);
  static const Color lightTextTertiary = Color(0xFF8E8E93);
  static const Color lightTextPlaceholder = Color(0xFFC7C7CC);

  // Dark theme colors
  static const Color darkBackground = Color(0xFF1C1C1E);
  static const Color darkSurface = Color(0xFF2C2C2E);
  static const Color darkSidebar = Color(0xFF1C1C1E);
  static const Color darkSidebarSelected = Color(0xFF3A2A2C);
  static const Color darkBorder = Color(0xFF38383A);
  static const Color darkDivider = Color(0xFF38383A);

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFAEAEB2);
  static const Color darkTextTertiary = Color(0xFF636366);
  static const Color darkTextPlaceholder = Color(0xFF48484A);

  // Priority colors for WBS nodes
  static const Color priorityHigh = Color(0xFFFF3B30);
  static const Color priorityMedium = Color(0xFFFF9500);
  static const Color priorityLow = Color(0xFF34C759);

  // Project status colors
  static const Color statusNotStarted = Color(0xFF8E8E93);
  static const Color statusInProgress = Color(0xFF007AFF);
  static const Color statusCompleted = Color(0xFF34C759);
  static const Color statusOnHold = Color(0xFFFF9500);
  static const Color statusCancelled = Color(0xFFFF3B30);

  // Gantt chart colors
  static const Color ganttTask = Color(0xFF007AFF);
  static const Color ganttMilestone = Color(0xFFDA4453);
  static const Color ganttCriticalPath = Color(0xFFFF3B30);
  static const Color ganttDependency = Color(0xFF8E8E93);
  static const Color ganttToday = Color(0xFFDA4453);
  static const Color ganttWeekend = Color(0xFFF5F5F5);

  // Card shadows
  static const List<BoxShadow> cardShadowLight = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> cardShadowDark = [
    BoxShadow(
      color: Color(0x20000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Get color for project status
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'not_started':
        return statusNotStarted;
      case 'in_progress':
        return statusInProgress;
      case 'completed':
        return statusCompleted;
      case 'on_hold':
        return statusOnHold;
      case 'cancelled':
        return statusCancelled;
      default:
        return statusNotStarted;
    }
  }

  /// Get color for priority level (1-4, 4 being highest)
  static Color getPriorityColor(int priority) {
    switch (priority) {
      case 4:
        return priorityHigh;
      case 3:
        return priorityMedium;
      case 2:
        return priorityLow;
      default:
        return Colors.transparent;
    }
  }
}
