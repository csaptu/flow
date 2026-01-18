# Flow Tasks - Detailed Plan

## Overview

Flow Tasks is the **simple, fast task capture app**. It bridges Google Tasks simplicity with TickTick power, using AI to clean up "clumsy" descriptions and break complex tasks into actionable steps.

**Core Principles:**
- Maximum 2 layers (Parent + Child). If something needs more depth, it graduates to Flow Projects.
- **Two-tab UI**: Personal tasks + "Assigned to Me" (from projects)
- Personal → Project promotion is a **COPY** operation (not move)

**Data Architecture:**
- Personal tasks stored in `tasks_db` (owned by tasks-service)
- "Assigned to Me" tasks read from projects-service API (external API for Flutter app)
- Cross-domain data (users, subscriptions, plans) accessed via `shared/repository` (Go imports, not HTTP)
- When promoting to project: task is COPIED, user chooses to keep/delete personal version

**Design Inspiration:** [Bear App](https://bear.app/) - Apple Design Award winner known for its polished, minimal interface, beautiful typography, and distraction-free writing experience.

---

## 1. Design System (Bear-Inspired)

### 1.1 Design Philosophy

Following Bear's award-winning approach:

| Principle | Implementation |
|-----------|----------------|
| **Blank Canvas** | Content-first, UI fades into background |
| **Distraction-Free** | Focus mode hides sidebar and toolbars |
| **Beautiful Typography** | Carefully chosen fonts and spacing |
| **Soft & Approachable** | Rounded corners, subtle shadows |
| **Liquid Glass** | Frosted translucent panels (iOS 26+) |
| **Progressive Disclosure** | Show complexity only when needed |

### 1.2 Color System

```dart
// lib/core/constants/app_colors.dart

/// Bear-inspired color palette
/// Primary accent: Warm red-orange (Bear's signature)
/// Secondary: Soft neutrals with depth

class FlowColors {
  // === PRIMARY (Bear's signature red-orange) ===
  static const Color primary = Color(0xFFDA4453);      // Bear red
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
  static const Color lightTextPrimary = Color(0xFF2C2C2E);    // Almost black
  static const Color lightTextSecondary = Color(0xFF636366);  // Gray
  static const Color lightTextTertiary = Color(0xFF8E8E93);   // Light gray
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
}
```

### 1.3 Typography System

```dart
// lib/core/constants/app_typography.dart

/// Bear-inspired typography
/// - Clean, readable fonts
/// - Generous line heights (1.6-1.8)
/// - Subtle font weight differences

class FlowTypography {
  // Font families
  // Primary: System font for UI (SF Pro on Apple, Roboto on Android)
  // Editor: Optional custom fonts for task descriptions

  static const String fontFamilyUI = '.SF Pro Text'; // Falls back to system
  static const String fontFamilyEditor = 'Inter';    // Or 'Source Sans Pro'
  static const String fontFamilyMono = 'SF Mono';    // For code/dates

  // === DISPLAY (Large titles) ===
  static const TextStyle displayLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
  );

  // === HEADLINES ===
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.35,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // === BODY (Main content) ===
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.6,  // Bear uses generous line height
    letterSpacing: 0.1,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.6,
    letterSpacing: 0.1,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // === LABELS (UI elements) ===
  static const TextStyle labelLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    textBaseline: TextBaseline.alphabetic,
  );

  // === SPECIAL ===
  // Task title (slightly bolder for scanning)
  static const TextStyle taskTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  // Completed task (strikethrough)
  static const TextStyle taskTitleCompleted = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
    decoration: TextDecoration.lineThrough,
    decorationColor: Color(0xFF8E8E93),
  );

  // Sidebar items
  static const TextStyle sidebarItem = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // Metadata (dates, counts)
  static const TextStyle metadata = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );
}
```

### 1.4 Spacing & Layout

```dart
// lib/core/constants/app_spacing.dart

/// Bear-inspired spacing
/// - Generous whitespace
/// - Consistent rhythm
/// - Breathable layouts

class FlowSpacing {
  // Base unit (4px grid)
  static const double unit = 4.0;

  // Spacing scale
  static const double xxs = 2.0;   // 2px
  static const double xs = 4.0;    // 4px
  static const double sm = 8.0;    // 8px
  static const double md = 16.0;   // 16px
  static const double lg = 24.0;   // 24px
  static const double xl = 32.0;   // 32px
  static const double xxl = 48.0;  // 48px
  static const double xxxl = 64.0; // 64px

  // Component-specific
  static const double sidebarWidth = 280.0;
  static const double sidebarCollapsedWidth = 72.0;
  static const double taskListMaxWidth = 720.0;  // Readable line width
  static const double taskItemHeight = 56.0;
  static const double taskItemPaddingH = 16.0;
  static const double taskItemPaddingV = 12.0;

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
```

### 1.5 Component Library

#### Sidebar (Bear-style collapsible)

```dart
// lib/shared/widgets/flow_sidebar.dart

class FlowSidebar extends StatelessWidget {
  final bool isCollapsed;
  final int selectedIndex;
  final Function(int) onItemTap;

  static const _items = [
    SidebarItem(icon: Icons.inbox_rounded, label: 'Inbox', count: 12),
    SidebarItem(icon: Icons.today_rounded, label: 'Today', count: 3),
    SidebarItem(icon: Icons.calendar_month_rounded, label: 'Upcoming'),
    SidebarItem(icon: Icons.check_circle_outline_rounded, label: 'Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: isCollapsed ? FlowSpacing.sidebarCollapsedWidth : FlowSpacing.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(
          right: BorderSide(
            color: colors.divider,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(context),
          const SizedBox(height: FlowSpacing.md),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _items.length,
              itemBuilder: (context, index) => _buildItem(
                context,
                _items[index],
                isSelected: index == selectedIndex,
                onTap: () => onItemTap(index),
              ),
            ),
          ),

          // Settings at bottom
          _buildSettingsItem(context),
          const SizedBox(height: FlowSpacing.md),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    SidebarItem item, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? colors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: FlowTypography.sidebarItem.copyWith(
                        color: isSelected ? colors.textPrimary : colors.textSecondary,
                      ),
                    ),
                  ),
                  if (item.count != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(FlowSpacing.radiusFull),
                      ),
                      child: Text(
                        '${item.count}',
                        style: FlowTypography.labelSmall.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

#### Task Tile (Bear-style minimal)

```dart
// lib/features/tasks/presentation/widgets/bear_task_tile.dart

class BearTaskTile extends StatelessWidget {
  final Task task;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;
    final isCompleted = task.status == TaskStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          child: Padding(
            padding: FlowSpacing.listItemPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox (Bear-style: minimal circle)
                _BearCheckbox(
                  isChecked: isCompleted,
                  onTap: onComplete,
                  priority: task.priority,
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        task.aiSummary ?? task.title,
                        style: isCompleted
                            ? FlowTypography.taskTitleCompleted.copyWith(
                                color: colors.textTertiary,
                              )
                            : FlowTypography.taskTitle.copyWith(
                                color: colors.textPrimary,
                              ),
                      ),

                      // Metadata row
                      if (_hasMetadata) ...[
                        const SizedBox(height: 4),
                        _buildMetadataRow(context),
                      ],
                    ],
                  ),
                ),

                // Expand button (if has children)
                if (task.hasChildren)
                  IconButton(
                    icon: AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: colors.textTertiary,
                      ),
                    ),
                    onPressed: onExpand,
                    splashRadius: 16,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;
    final parts = <Widget>[];

    // Due date
    if (task.dueDate != null) {
      final isOverdue = task.dueDate!.isBefore(DateTime.now()) &&
          task.status != TaskStatus.completed;
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 12,
            color: isOverdue ? colors.error : colors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            _formatDate(task.dueDate!),
            style: FlowTypography.metadata.copyWith(
              color: isOverdue ? colors.error : colors.textTertiary,
            ),
          ),
        ],
      ));
    }

    // Steps progress
    if (task.aiSteps.isNotEmpty) {
      final done = task.aiSteps.where((s) => s.done).length;
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.checklist_rounded,
            size: 12,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            '$done/${task.aiSteps.length}',
            style: FlowTypography.metadata.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ],
      ));
    }

    return Wrap(
      spacing: 12,
      children: parts,
    );
  }
}

/// Bear-style checkbox: minimal circle with soft animation
class _BearCheckbox extends StatelessWidget {
  final bool isChecked;
  final VoidCallback onTap;
  final int priority;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;
    final priorityColor = _getPriorityColor(priority, colors);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isChecked ? colors.primary : Colors.transparent,
          border: Border.all(
            color: isChecked ? colors.primary : priorityColor ?? colors.border,
            width: isChecked ? 0 : 1.5,
          ),
        ),
        child: isChecked
            ? const Icon(
                Icons.check_rounded,
                size: 14,
                color: Colors.white,
              )
            : null,
      ),
    );
  }

  Color? _getPriorityColor(int priority, FlowColorScheme colors) {
    switch (priority) {
      case 4: return FlowColors.priorityUrgent;
      case 3: return FlowColors.priorityHigh;
      case 2: return FlowColors.priorityMedium;
      default: return null;
    }
  }
}
```

#### Quick Add Bar (Bear-style floating input)

```dart
// lib/features/tasks/presentation/widgets/quick_add_bar.dart

class QuickAddBar extends StatefulWidget {
  final Function(String) onSubmit;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.symmetric(
        horizontal: _hasFocus ? 0 : 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(
          _hasFocus ? 0 : FlowSpacing.radiusMd,
        ),
        boxShadow: _hasFocus ? null : FlowColors.cardShadowLight,
        border: Border.all(
          color: _hasFocus ? colors.primary : colors.border.withOpacity(0.5),
          width: _hasFocus ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.add_rounded,
            color: _hasFocus ? colors.primary : colors.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: FlowTypography.bodyMedium.copyWith(
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Add a task...',
                hintStyle: FlowTypography.bodyMedium.copyWith(
                  color: colors.textPlaceholder,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: _handleSubmit,
              onTap: () => setState(() => _hasFocus = true),
              onEditingComplete: () => setState(() => _hasFocus = false),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: colors.primary,
                size: 20,
              ),
              onPressed: () => _handleSubmit(_controller.text),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _handleSubmit(String text) {
    if (text.trim().isEmpty) return;
    widget.onSubmit(text.trim());
    _controller.clear();
    _focusNode.unfocus();
    setState(() => _hasFocus = false);
  }
}
```

### 1.6 Animation Guidelines

```dart
// lib/core/constants/app_animations.dart

/// Bear-inspired animations: Subtle, smooth, purposeful

class FlowAnimations {
  // Durations (Bear uses quick, subtle animations)
  static const Duration fastest = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration slower = Duration(milliseconds: 400);

  // Curves (smooth, organic feel)
  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve bounceCurve = Curves.easeOutBack;
  static const Curve sharpCurve = Curves.easeOutQuart;

  // Common animations
  static const fadeIn = Duration(milliseconds: 150);
  static const slideIn = Duration(milliseconds: 200);
  static const expand = Duration(milliseconds: 200);
  static const checkmark = Duration(milliseconds: 300);

  // Stagger delays (for list animations)
  static const staggerDelay = Duration(milliseconds: 30);
}

// Usage example:
// AnimatedContainer(
//   duration: FlowAnimations.normal,
//   curve: FlowAnimations.defaultCurve,
//   ...
// )
```

### 1.7 Focus Mode (Bear's signature feature)

```dart
// lib/features/focus/presentation/focus_mode_wrapper.dart

/// Focus mode: Hides sidebar and extra UI for distraction-free task viewing

class FocusModeWrapper extends ConsumerWidget {
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFocusMode = ref.watch(focusModeProvider);
    final colors = Theme.of(context).extension<FlowColorScheme>()!;

    return Stack(
      children: [
        // Main content
        AnimatedPadding(
          duration: FlowAnimations.slow,
          curve: FlowAnimations.defaultCurve,
          padding: EdgeInsets.only(
            left: isFocusMode ? 0 : FlowSpacing.sidebarWidth,
          ),
          child: child,
        ),

        // Sidebar (slides out in focus mode)
        AnimatedPositioned(
          duration: FlowAnimations.slow,
          curve: FlowAnimations.defaultCurve,
          left: isFocusMode ? -FlowSpacing.sidebarWidth : 0,
          top: 0,
          bottom: 0,
          child: const FlowSidebar(),
        ),

        // Focus mode exit hint (shows briefly on mouse move)
        if (isFocusMode)
          Positioned(
            top: 16,
            left: 16,
            child: _FocusExitHint(
              onExit: () => ref.read(focusModeProvider.notifier).exit(),
            ),
          ),
      ],
    );
  }
}

class _FocusExitHint extends StatefulWidget {
  final VoidCallback onExit;

  @override
  State<_FocusExitHint> createState() => _FocusExitHintState();
}

class _FocusExitHintState extends State<_FocusExitHint> {
  bool _isVisible = false;
  Timer? _hideTimer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FlowColorScheme>()!;

    return MouseRegion(
      onEnter: (_) => _showHint(),
      child: AnimatedOpacity(
        duration: FlowAnimations.fast,
        opacity: _isVisible ? 1.0 : 0.0,
        child: Material(
          color: colors.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          child: InkWell(
            onTap: widget.onExit,
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fullscreen_exit_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Exit Focus',
                    style: FlowTypography.labelSmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Esc',
                    style: FlowTypography.labelSmall.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showHint() {
    setState(() => _isVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isVisible = false);
    });
  }
}
```

### 1.8 Theme Configuration

```dart
// lib/core/theme/flow_theme.dart

class FlowTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: FlowColors.primary,
        onPrimary: Colors.white,
        surface: FlowColors.lightSurface,
        onSurface: FlowColors.lightTextPrimary,
        background: FlowColors.lightBackground,
        onBackground: FlowColors.lightTextPrimary,
        error: FlowColors.error,
      ),
      scaffoldBackgroundColor: FlowColors.lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: FlowColors.lightSurface,
        foregroundColor: FlowColors.lightTextPrimary,
        elevation: 0,
        titleTextStyle: FlowTypography.headlineSmall.copyWith(
          color: FlowColors.lightTextPrimary,
        ),
      ),
      cardTheme: CardTheme(
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
      ),
      dividerTheme: const DividerThemeData(
        color: FlowColors.lightDivider,
        thickness: 0.5,
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
      colorScheme: ColorScheme.dark(
        primary: FlowColors.primary,
        onPrimary: Colors.white,
        surface: FlowColors.darkSurface,
        onSurface: FlowColors.darkTextPrimary,
        background: FlowColors.darkBackground,
        onBackground: FlowColors.darkTextPrimary,
        error: FlowColors.error,
      ),
      scaffoldBackgroundColor: FlowColors.darkBackground,
      // ... similar dark theme config
      extensions: [
        FlowColorScheme.dark(),
      ],
    );
  }
}

/// Theme extension for custom colors
class FlowColorScheme extends ThemeExtension<FlowColorScheme> {
  final Color primary;
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

  FlowColorScheme({
    required this.primary,
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
  });

  factory FlowColorScheme.light() => FlowColorScheme(
        primary: FlowColors.primary,
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
      );

  factory FlowColorScheme.dark() => FlowColorScheme(
        primary: FlowColors.primary,
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
      );

  @override
  ThemeExtension<FlowColorScheme> copyWith({...}) => ...;

  @override
  ThemeExtension<FlowColorScheme> lerp(other, t) => ...;
}
```

---

## 2. User Experience Flow

### 1.1 Task Capture (The "Inbox")

```
┌─────────────────────────────────────────────────────────┐
│  + Add task...                                          │
│  ─────────────────────────────────────────────────────  │
│  □ Call plumber about leaky sink tomorrow              │
│  □ Prepare Q3 budget presentation                      │
│      └─ □ Gather revenue data                          │
│      └─ □ Create slides                                │
│      └─ □ Review with Sarah                            │
│  ☑ Buy groceries                                       │
│  □ Email John about project status                     │
└─────────────────────────────────────────────────────────┘
```

**User Input → AI Processing:**
1. User types: "Need to fix that thing in bathroom, the water keeps dripping idk maybe the faucet or something"
2. AI cleans: "Fix bathroom faucet leak"
3. AI generates steps:
   - Turn off water supply valve
   - Remove faucet handle
   - Replace washer/O-ring
   - Test for leaks
4. AI assesses complexity: MEDIUM (4 steps, DIY possible)

### 1.2 The Two-Layer Limit

**Why 2 layers:**
- Keeps the app fast and focused
- Prevents analysis paralysis
- Forces complex work to graduate to Projects

**How it works:**
- **Layer 0 (Parent):** The main task visible in list
- **Layer 1 (Children):** Sub-tasks shown when parent is expanded
- **Layer 2+:** Blocked in Tasks app → "This task is complex. Convert to Project?"

### 1.3 AI Features & Pricing Tiers

#### Pricing Tiers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PRICING TIERS                                      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│                 │ FREE            │ LIGHT           │ PREMIUM         │
│                 │ $0              │ $5/mo           │ $12/mo          │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Tasks           │ Unlimited       │ Unlimited       │ Unlimited       │
│ Projects        │ 1               │ 5               │ Unlimited       │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ AI FEATURES     │                 │                 │                 │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Clean Title     │ ✓ (20/day)      │ ✓ Unlimited     │ ✓ Unlimited     │
│ Clean Desc      │ ✓ (20/day)      │ ✓ Unlimited     │ ✓ Unlimited     │
│ Smart Dates     │ ✓ Unlimited     │ ✓ Unlimited     │ ✓ Unlimited     │
│ Decompose       │ ✗               │ ✓ (30/day)      │ ✓ Unlimited     │
│ Complexity      │ ✗               │ ✓ Unlimited     │ ✓ Unlimited     │
│ Entity Extract  │ ✗               │ ✓ Unlimited     │ ✓ Unlimited     │
│ Recurring       │ ✗               │ ✓ Unlimited     │ ✓ Unlimited     │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ AGENTIC         │                 │                 │                 │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Auto-Group      │ ✗               │ ✓ (10/day)      │ ✓ Unlimited     │
│ Reminder        │ ✓ (5/day)       │ ✓ (20/day)      │ ✓ Unlimited     │
│ Draft Email     │ ✗               │ ✓ (10/day)      │ ✓ Unlimited     │
│ Draft Calendar  │ ✗               │ ✓ (10/day)      │ ✓ Unlimited     │
│ SEND Email      │ ✗               │ ✗               │ ✓ Unlimited     │
│ SEND Calendar   │ ✗               │ ✗               │ ✓ Unlimited     │
├─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ AI SETTINGS     │ Basic           │ Full            │ Full + Custom   │
│                 │                 │                 │ Prompts         │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

#### Payment Integration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PAYMENT INTEGRATION                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┬───────────────────────────────────────────────────────────┐
│ PLATFORM        │ PAYMENT METHOD                                            │
├─────────────────┼───────────────────────────────────────────────────────────┤
│ iOS / iPadOS    │ Apple In-App Purchase (StoreKit 2)                        │
│                 │ - Subscription managed via App Store Connect              │
│                 │ - Apple takes 15-30% commission                           │
│                 │ - Required for apps distributed via App Store             │
├─────────────────┼───────────────────────────────────────────────────────────┤
│ Android         │ Google Play Billing Library                               │
│                 │ - Subscription managed via Google Play Console            │
│                 │ - Google takes 15-30% commission                          │
│                 │ - Required for apps distributed via Play Store            │
├─────────────────┼───────────────────────────────────────────────────────────┤
│ Web             │ Paddle (Merchant of Record)                               │
│ macOS (direct)  │ - Paddle handles VAT/GST/sales tax globally               │
│ Windows         │ - Paddle Checkout overlay                                 │
│ Linux           │ - 5% + $0.50 per transaction                              │
│                 │ - Payout via Payoneer (VN-friendly)                       │
│                 │ - No need for own tax compliance                          │
└─────────────────┴───────────────────────────────────────────────────────────┘
```

**Why Paddle (Merchant of Record):**
- Paddle is the seller of record → handles all tax compliance (VAT, GST, sales tax)
- Supports payout to Vietnam via Payoneer
- No need to register for tax in 100+ countries
- Handles chargebacks, fraud, invoicing
- You receive net revenue after Paddle's cut

**Architecture:**

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   iOS/iPadOS App              Android App                 Web/Desktop        │
│   ┌──────────┐                ┌──────────┐                ┌──────────┐       │
│   │ StoreKit │                │ Play     │                │ Paddle   │       │
│   │    2     │                │ Billing  │                │ Checkout │       │
│   └────┬─────┘                └────┬─────┘                └────┬─────┘       │
│        │                           │                           │             │
│        ▼                           ▼                           ▼             │
│   ┌──────────┐                ┌──────────┐                ┌──────────┐       │
│   │  Apple   │                │  Google  │                │  Paddle  │       │
│   │ Servers  │                │ Servers  │                │ (MoR)    │       │
│   └────┬─────┘                └────┬─────┘                └────┬─────┘       │
│        │                           │                           │             │
│        │    Server-to-Server       │    Server-to-Server       │  Webhooks   │
│        │    Notifications          │    Notifications          │             │
│        ▼                           ▼                           ▼             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         FLOW BACKEND                                 │   │
│   │                                                                      │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │                 Subscription Service                         │   │   │
│   │   │  - Validate receipts (Apple/Google)                         │   │   │
│   │   │  - Process Paddle webhooks                                  │   │   │
│   │   │  - Unified subscription state                               │   │   │
│   │   │  - Grace period handling                                    │   │   │
│   │   └─────────────────────────────────────────────────────────────┘   │   │
│   │                              │                                       │   │
│   │                              ▼                                       │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │                    shared_db.subscriptions                   │   │   │
│   │   └─────────────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         PAYOUT FLOW                                  │   │
│   │   Paddle ──► Payoneer ──► Vietnam Bank Account                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Backend Schema:**

```sql
-- shared_db: migrations/000011_subscriptions.up.sql

CREATE TYPE subscription_tier AS ENUM ('free', 'light', 'premium');
CREATE TYPE payment_provider AS ENUM ('apple', 'google', 'paddle');
CREATE TYPE subscription_status AS ENUM (
    'active',
    'grace_period',    -- Payment failed, still has access
    'expired',
    'cancelled'        -- User cancelled, active until period end
);

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Subscription details
    tier subscription_tier NOT NULL DEFAULT 'free',
    status subscription_status NOT NULL DEFAULT 'active',

    -- Payment provider
    provider payment_provider,
    provider_subscription_id VARCHAR(255),  -- Apple/Google/Paddle sub ID
    provider_customer_id VARCHAR(255),      -- Paddle customer ID

    -- Billing period
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,

    -- Grace period (payment retry)
    grace_period_end TIMESTAMPTZ,

    -- Cancellation
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    cancelled_at TIMESTAMPTZ,

    -- Receipt validation
    latest_receipt TEXT,                    -- Apple receipt / Google token
    receipt_validated_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id)
);

CREATE INDEX idx_subscriptions_provider ON subscriptions(provider, provider_subscription_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_period_end ON subscriptions(current_period_end);

-- Payment history for auditing
CREATE TABLE payment_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id),

    provider payment_provider NOT NULL,
    provider_transaction_id VARCHAR(255),

    -- For Paddle: this is NET amount (after Paddle's cut + taxes)
    amount_cents INTEGER NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',

    tier subscription_tier NOT NULL,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,

    status VARCHAR(50) NOT NULL,  -- succeeded, failed, refunded
    failure_reason TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_payment_history_user ON payment_history(user_id);
```

**Implementation Notes:**

| Platform | Key Considerations |
|----------|-------------------|
| **iOS/iPadOS** | Use StoreKit 2 (async/await). Verify receipts server-side via App Store Server API. Handle family sharing. |
| **Android** | Use BillingClient 5+. Acknowledge purchases within 3 days. Verify via Google Play Developer API. |
| **Paddle** | Use Paddle.js for checkout overlay. Handle webhooks: `subscription.created`, `subscription.updated`, `subscription.cancelled`, `transaction.completed`. Paddle handles all tax/VAT. |
| **Cross-platform** | User can only have ONE active subscription. If subscribed via Apple, show "Manage in App Store" on other platforms. |

**Paddle Webhook Events:**

| Event | Action |
|-------|--------|
| `subscription.created` | Create/update subscription record, set status=active |
| `subscription.updated` | Update tier, billing period |
| `subscription.cancelled` | Set cancel_at_period_end=true |
| `subscription.past_due` | Set status=grace_period |
| `transaction.completed` | Record in payment_history |

**Upsell Flow (Draft → Send):**
```
┌─────────────────────────────────────────────────────────────────┐
│ Light user drafts an email                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  📧 Draft: Email to Sarah                                       │
│                                                                 │
│  Subject: Project Update                                        │
│  Body: Hi Sarah, just wanted to let you know...                 │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ [Copy to Clipboard]  [Open in Mail App]                   │ │
│  │                                                           │ │
│  │ ────────────────── OR ──────────────────                  │ │
│  │                                                           │ │
│  │ [⭐ Send directly with Premium]                           │ │
│  │  One tap send. No copy-paste.                             │ │
│  │                                                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Feature Summary

| Feature | Trigger | AI Action | Tier | Default |
|---------|---------|-----------|------|---------|
| Clean Title | On save | Shorten to <8 words | Free | Auto |
| Clean Description | On save | Summarize to <15 words | Free | Auto |
| Smart Due Dates | On save | Parse "tomorrow" etc | Free | Auto |
| Decompose | User taps button | Create 2-5 steps | Light | Ask |
| Complexity Check | On save | Score 1-10 | Light | Auto |
| Entity Extraction | On save | Find people | Light | Auto |
| Recurring Detection | On save | Detect patterns | Light | Ask |
| **Auto-Group** | On save / manual | Group similar tasks | Light | Ask |
| Reminder | "remind me" | Schedule notification | Free* | Ask |
| **Draft Email** | "tell X", "email X" | Generate draft | Light | Ask |
| **Draft Calendar** | "meet with X" | Generate draft | Light | Ask |
| **Send Email** | Approve draft | Send via OAuth | Premium | Ask |
| **Send Calendar** | Approve draft | Create via OAuth | Premium | Ask |

#### Auto-Grouping Feature

AI automatically groups similar tasks and suggests group names:

```
┌─────────────────────────────────────────────────────────────────┐
│ BEFORE (ungrouped)                                              │
├─────────────────────────────────────────────────────────────────┤
│  □ Buy groceries                                                │
│  □ Fix bathroom faucet                                          │
│  □ Call dentist for appointment                                 │
│  □ Pick up dry cleaning                                         │
│  □ Schedule car service                                         │
│  □ Book flight to NYC                                           │
│  □ Call insurance company                                       │
│  □ Replace kitchen light bulb                                   │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼ AI Auto-Group
┌─────────────────────────────────────────────────────────────────┐
│ AFTER (grouped)                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  📞 Phone Calls                           ← AI-generated name   │
│    □ Call dentist for appointment                               │
│    □ Call insurance company                                     │
│                                                                 │
│  🏠 Home Maintenance                      ← AI-generated name   │
│    □ Fix bathroom faucet                                        │
│    □ Replace kitchen light bulb                                 │
│                                                                 │
│  🚗 Errands                               ← AI-generated name   │
│    □ Buy groceries                                              │
│    □ Pick up dry cleaning                                       │
│                                                                 │
│  📅 Appointments                          ← AI-generated name   │
│    □ Schedule car service                                       │
│    □ Book flight to NYC                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Non-Intrusive AI Prompts

AI suggestions should **never interrupt user flow**. Use passive indicators:

```
┌─────────────────────────────────────────────────────────────────┐
│ NON-INTRUSIVE AI SUGGESTIONS                                    │
└─────────────────────────────────────────────────────────────────┘

BAD (Intrusive - blocks user):
┌─────────────────────────────────────────────────────────────────┐
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │           AI wants to help!                                 │ │
│ │                                                             │ │
│ │  I noticed you wrote "email John". Would you like me to     │ │
│ │  draft an email for you?                                    │ │
│ │                                                             │ │
│ │              [Yes]  [No]  [Don't ask again]                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                          ↑ MODAL POPUP = BAD                    │
└─────────────────────────────────────────────────────────────────┘

GOOD (Non-intrusive - user can ignore):
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  □ Email John about the project update              📅 Today    │
│    ┌────────────────────────────────────────────┐              │
│    │ 📧 Draft available                      [→] │  ← Subtle   │
│    └────────────────────────────────────────────┘    chip      │
│                                                                 │
│  OR: Show in dedicated "AI Suggestions" section                 │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ✨ AI Suggestions (2)                            [Hide] │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                         │   │
│  │  📧 Draft email to John           [Create] [Dismiss]    │   │
│  │  📅 Schedule meeting with Sarah   [Create] [Dismiss]    │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Tasks                                                          │
│  ─────────────────────────────────────────────────────────────  │
│  □ Email John about the project update              📅 Today    │
│  □ Meet with Sarah to discuss roadmap               📅 Tomorrow │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### User Preferences (Per Feature)

Each AI feature can be configured by the user:

| Setting | Behavior |
|---------|----------|
| **Auto** | AI runs automatically, no prompt |
| **Ask** | AI suggests in non-intrusive way |
| **Off** | Feature disabled |

```dart
// Settings stored per user
class AIPreferences {
  AISetting cleanTitle;         // Auto, Ask, Off
  AISetting cleanDescription;   // Auto, Ask, Off
  AISetting decompose;          // Auto, Ask, Off
  AISetting complexityCheck;    // Auto, Ask, Off
  AISetting entityExtraction;   // Auto, Ask, Off
  AISetting smartDueDates;      // Auto, Ask, Off
  AISetting recurringDetection; // Auto, Ask, Off
  AISetting autoGroup;          // Auto, Ask, Off
  AISetting draftEmail;         // Auto, Ask, Off
  AISetting draftCalendar;      // Auto, Ask, Off
  AISetting sendEmail;          // Auto, Ask, Off (Premium only)
  AISetting sendCalendar;       // Auto, Ask, Off (Premium only)
  AISetting reminder;           // Auto, Ask, Off
}

enum AISetting { auto, ask, off }
```

### 1.4 User AI Settings (In-App)

Users can toggle features and view usage. **No prompt customization** - that's admin-only.

```
┌─────────────────────────────────────────────────────────────────┐
│ ← AI Settings                                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FEATURE CONTROLS                                               │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Clean Title                                    [Auto ▼]        │
│  Clean Description                              [Auto ▼]        │
│  Smart Due Dates                                [Auto ▼]        │
│  Decompose Tasks                                [Ask ▼]  ⭐     │
│  Auto-Group                                     [Ask ▼]  ⭐     │
│  Draft Emails                                   [Ask ▼]  ⭐     │
│  Draft Calendar                                 [Ask ▼]  ⭐     │
│  Send Email                                     [Ask ▼]  👑     │
│  Send Calendar                                  [Ask ▼]  👑     │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│  USAGE                                                          │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  Current Plan: Light                   [Upgrade to Premium]     │
│                                                                 │
│  Today:                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Decompose        ████████░░░░  8/30                     │   │
│  │ Auto-Group       ██░░░░░░░░░░  2/10                     │   │
│  │ Draft Email      ████░░░░░░░░  4/10                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│  DATA & PRIVACY                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  [Export My Data]     [Delete AI Data]                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.5 Admin Panel: AI & Prompt Configuration

**Admin-only dashboard** for configuring AI behavior, RAG settings, and prompts across all users.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ADMIN PANEL - AI CONFIGURATION                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  Flow Admin                                          admin@flow.app  [Logout]│
├────────────────┬────────────────────────────────────────────────────────────┤
│                │                                                            │
│  Dashboard     │  AI PROMPTS                                                │
│  Users         │  ────────────────────────────────────────────────────────  │
│  Billing       │                                                            │
│  ▶ AI Config   │  ┌──────────────────────────────────────────────────────┐ │
│    • Prompts   │  │ Feature           │ Status  │ Model      │ Actions   │ │
│    • RAG       │  ├──────────────────────────────────────────────────────┤ │
│    • Models    │  │ clean_title       │ ✓ Active│ gpt-4o-mini│ [Edit]    │ │
│    • Limits    │  │ clean_description │ ✓ Active│ gpt-4o-mini│ [Edit]    │ │
│  Analytics     │  │ decompose         │ ✓ Active│ gpt-4o     │ [Edit]    │ │
│  Logs          │  │ auto_group        │ ✓ Active│ gpt-4o     │ [Edit]    │ │
│                │  │ draft_email       │ ✓ Active│ gpt-4o     │ [Edit]    │ │
│                │  │ draft_calendar    │ ✓ Active│ gpt-4o     │ [Edit]    │ │
│                │  │ entity_extraction │ ✓ Active│ gpt-4o-mini│ [Edit]    │ │
│                │  └──────────────────────────────────────────────────────┘ │
│                │                                                            │
│                │  [+ Add New Prompt]                                        │
│                │                                                            │
└────────────────┴────────────────────────────────────────────────────────────┘
```

#### Prompt Editor (Admin)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ← Back to Prompts              Edit: clean_title              [Save] [Test] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  STATUS          [✓ Active]        MODEL         [gpt-4o-mini ▼]            │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  SYSTEM PROMPT                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ You are a task title optimizer. Given a user's raw task input,      │   │
│  │ create a clean, actionable title.                                   │   │
│  │                                                                     │   │
│  │ Rules:                                                              │   │
│  │ - Maximum 8 words                                                   │   │
│  │ - Start with action verb (Call, Fix, Send, Review, etc.)            │   │
│  │ - Remove filler words ("I need to", "maybe", "probably", "idk")     │   │
│  │ - Keep essential context (who, what)                                │   │
│  │ - Capitalize first letter only                                      │   │
│  │                                                                     │   │
│  │ Return ONLY the cleaned title, nothing else.                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  AVAILABLE VARIABLES                                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ {{original_title}}     User's raw title input                       │   │
│  │ {{original_desc}}      User's description (if any)                  │   │
│  │ {{detected_entities}}  People/places found in text                  │   │
│  │ {{detected_date}}      Date phrases found ("tomorrow", etc)         │   │
│  │ {{user_locale}}        User's language/region                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  TEST                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Input: "I gotta maybe call john tomorrow about that thing we        │   │
│  │         discussed last week idk"                                    │   │
│  │                                                      [Run Test]     │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ Output: "Call John about discussion"                                │   │
│  │ Tokens: 45 in / 6 out                                               │   │
│  │ Latency: 120ms                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  VERSION HISTORY                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ v3 (current)  Jan 15, 2024  "Added capitalization rule"   [Restore] │   │
│  │ v2            Jan 10, 2024  "Reduced max words to 8"      [Restore] │   │
│  │ v1            Jan 5, 2024   "Initial prompt"              [Restore] │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### RAG Configuration (Admin)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ← Back                         RAG Configuration                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ENTITY EXTRACTION                                                          │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  Enable entity learning                          [✓ On]                     │
│  Extract people, places, orgs from task text                                │
│                                                                             │
│  Entity types to extract:                                                   │
│  [✓] People      [✓] Organizations     [ ] Locations     [ ] Products      │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  CONTEXT INJECTION                                                          │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  Per-feature RAG settings:                                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Feature         │ Entities │ History │ History Limit │ User Style  │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ clean_title     │ [ ]      │ [ ]     │ -             │ [ ]         │   │
│  │ clean_desc      │ [ ]      │ [ ]     │ -             │ [ ]         │   │
│  │ decompose       │ [✓]      │ [✓]     │ 10 tasks      │ [ ]         │   │
│  │ auto_group      │ [✓]      │ [✓]     │ 50 tasks      │ [ ]         │   │
│  │ draft_email     │ [✓]      │ [✓]     │ 20 tasks      │ [✓]         │   │
│  │ draft_calendar  │ [✓]      │ [✓]     │ 10 tasks      │ [✓]         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  USER STYLE LEARNING                                                        │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  Enable style learning                           [✓ On]                     │
│  Learn user's writing tone from sent emails                                 │
│                                                                             │
│  Attributes to learn:                                                       │
│  [✓] Tone (formal/casual)     [✓] Greeting style    [✓] Sign-off style     │
│  [✓] Average length           [ ] Vocabulary level                          │
│                                                                             │
│  Min samples before applying: [5] emails                                    │
│                                                                             │
│  [Save Configuration]                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Model & Rate Limit Configuration (Admin)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ← Back                         Models & Limits                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LLM PROVIDERS                                                              │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  Primary:    [OpenAI ▼]        API Key: sk-xxxxx...xxxxx    [Test] ✓        │
│  Fallback:   [Anthropic ▼]     API Key: sk-ant-xxx...xxx    [Test] ✓        │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  MODEL ASSIGNMENT                                                           │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Feature            │ Model          │ Max Tokens │ Temperature      │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ clean_title        │ gpt-4o-mini    │ 50         │ 0.3              │   │
│  │ clean_description  │ gpt-4o-mini    │ 100        │ 0.3              │   │
│  │ decompose          │ gpt-4o         │ 500        │ 0.5              │   │
│  │ auto_group         │ gpt-4o         │ 500        │ 0.4              │   │
│  │ draft_email        │ gpt-4o         │ 300        │ 0.7              │   │
│  │ draft_calendar     │ gpt-4o         │ 200        │ 0.5              │   │
│  │ entity_extraction  │ gpt-4o-mini    │ 200        │ 0.2              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  TIER RATE LIMITS (per user, per day)                                       │
│  ───────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Feature            │ Free     │ Light    │ Premium                  │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ clean_title        │ 20       │ ∞        │ ∞                        │   │
│  │ clean_description  │ 20       │ ∞        │ ∞                        │   │
│  │ decompose          │ 0        │ 30       │ ∞                        │   │
│  │ auto_group         │ 0        │ 10       │ ∞                        │   │
│  │ draft_email        │ 0        │ 10       │ ∞                        │   │
│  │ draft_calendar     │ 0        │ 10       │ ∞                        │   │
│  │ send_email         │ 0        │ 0        │ ∞                        │   │
│  │ send_calendar      │ 0        │ 0        │ ∞                        │   │
│  │ reminder           │ 5        │ 20       │ ∞                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  [Save Configuration]                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Backend: Admin Configuration

```go
// shared/ai/admin_config.go

// Global AI configuration (admin-managed)
type AIAdminConfig struct {
    ID          uuid.UUID `json:"id"`
    FeatureType string    `json:"feature_type"`

    // Status
    IsActive bool `json:"is_active"`

    // Model settings
    Provider     string  `json:"provider"`     // openai, anthropic, google
    Model        string  `json:"model"`        // gpt-4o, claude-3, etc.
    MaxTokens    int     `json:"max_tokens"`
    Temperature  float64 `json:"temperature"`

    // Prompt
    SystemPrompt string `json:"system_prompt"`
    Version      int    `json:"version"`

    // RAG settings
    IncludeEntities bool `json:"include_entities"`
    IncludeHistory  bool `json:"include_history"`
    HistoryLimit    int  `json:"history_limit"`
    IncludeStyle    bool `json:"include_style"`

    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
}

// Rate limits per tier
type TierRateLimits struct {
    FeatureType string `json:"feature_type"`
    FreeTier    int    `json:"free_tier"`    // -1 = disabled, 0 = unlimited
    LightTier   int    `json:"light_tier"`
    PremiumTier int    `json:"premium_tier"`
}

// Prompt version history
type PromptVersion struct {
    ID          uuid.UUID `json:"id"`
    FeatureType string    `json:"feature_type"`
    Version     int       `json:"version"`
    Prompt      string    `json:"prompt"`
    ChangedBy   uuid.UUID `json:"changed_by"`
    ChangeNote  string    `json:"change_note"`
    CreatedAt   time.Time `json:"created_at"`
}
```

```sql
-- shared_db: migrations/000010_ai_admin_config.up.sql

-- Admin-managed AI configuration (global, not per-user)
CREATE TABLE ai_admin_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    feature_type VARCHAR(50) UNIQUE NOT NULL,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Model
    provider VARCHAR(50) DEFAULT 'openai',
    model VARCHAR(100) DEFAULT 'gpt-4o-mini',
    max_tokens INTEGER DEFAULT 100,
    temperature DECIMAL(3,2) DEFAULT 0.5,

    -- Prompt
    system_prompt TEXT NOT NULL,
    version INTEGER DEFAULT 1,

    -- RAG
    include_entities BOOLEAN DEFAULT FALSE,
    include_history BOOLEAN DEFAULT FALSE,
    history_limit INTEGER DEFAULT 10,
    include_style BOOLEAN DEFAULT FALSE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Prompt version history
CREATE TABLE ai_prompt_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    feature_type VARCHAR(50) NOT NULL,
    version INTEGER NOT NULL,
    system_prompt TEXT NOT NULL,
    changed_by UUID REFERENCES users(id),
    change_note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(feature_type, version)
);

-- Tier rate limits
CREATE TABLE ai_tier_limits (
    feature_type VARCHAR(50) PRIMARY KEY,
    free_limit INTEGER DEFAULT 0,      -- 0 = disabled, -1 = unlimited
    light_limit INTEGER DEFAULT 0,
    premium_limit INTEGER DEFAULT -1   -- -1 = unlimited
);

-- User usage tracking (unchanged)
CREATE TABLE ai_usage_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    feature_type VARCHAR(50) NOT NULL,
    usage_date DATE NOT NULL DEFAULT CURRENT_DATE,
    count INTEGER DEFAULT 0,
    UNIQUE(user_id, feature_type, usage_date)
);

CREATE INDEX idx_usage_user_date ON ai_usage_tracking(user_id, usage_date);

-- Insert default rate limits
INSERT INTO ai_tier_limits (feature_type, free_limit, light_limit, premium_limit) VALUES
    ('clean_title', 20, -1, -1),
    ('clean_description', 20, -1, -1),
    ('smart_dates', -1, -1, -1),
    ('decompose', 0, 30, -1),
    ('complexity', 0, -1, -1),
    ('entity_extraction', 0, -1, -1),
    ('recurring', 0, -1, -1),
    ('auto_group', 0, 10, -1),
    ('draft_email', 0, 10, -1),
    ('draft_calendar', 0, 10, -1),
    ('send_email', 0, 0, -1),
    ('send_calendar', 0, 0, -1),
    ('reminder', 5, 20, -1);
```

#### Original Input Preservation

When AI modifies user input, **always save the original** for reference:

```
┌─────────────────────────────────────────────────────────────────┐
│ Task Detail                                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Fix bathroom faucet leak                    ← AI-cleaned title │
│                                                                 │
│  Turn off water, replace washer              ← AI summary       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 📝 Original input                              [Restore] │   │
│  │                                                         │   │
│  │ "Need to fix that thing in bathroom, the water keeps    │   │
│  │  dripping idk maybe the faucet or something"            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

```sql
-- tasks_db.tasks table
CREATE TABLE tasks (
    ...
    -- AI-cleaned versions
    title TEXT NOT NULL,
    description TEXT,
    ai_summary TEXT,

    -- Original user input (preserved)
    original_title TEXT,          -- What user actually typed
    original_description TEXT,    -- What user actually typed
    ...
);
```

---

## 2. Flutter App Architecture

### 2.1 Project Structure

```
apps/flow_tasks/
├── lib/
│   ├── main.dart
│   ├── app.dart                      # App widget, routing
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_typography.dart
│   │   │   └── app_spacing.dart
│   │   ├── theme/
│   │   │   ├── light_theme.dart
│   │   │   └── dark_theme.dart
│   │   ├── router/
│   │   │   └── app_router.dart       # GoRouter config
│   │   └── di/
│   │       └── injection.dart        # Dependency injection
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── auth_repository.dart
│   │   │   │   └── auth_local_source.dart
│   │   │   ├── domain/
│   │   │   │   ├── user.dart
│   │   │   │   └── auth_state.dart
│   │   │   ├── presentation/
│   │   │   │   ├── login_screen.dart
│   │   │   │   ├── register_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── oauth_button.dart
│   │   │   │       └── auth_form.dart
│   │   │   └── providers/
│   │   │       └── auth_provider.dart
│   │   │
│   │   ├── tasks/
│   │   │   ├── data/
│   │   │   │   ├── task_repository.dart
│   │   │   │   ├── task_local_source.dart    # Drift
│   │   │   │   └── task_remote_source.dart   # API
│   │   │   ├── domain/
│   │   │   │   ├── task.dart
│   │   │   │   ├── task_step.dart
│   │   │   │   └── task_filter.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   ├── task_list_screen.dart
│   │   │   │   │   ├── task_detail_screen.dart
│   │   │   │   │   └── task_edit_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── task_tile.dart
│   │   │   │       ├── task_input.dart
│   │   │   │       ├── step_checklist.dart
│   │   │   │       ├── priority_picker.dart
│   │   │   │       └── date_picker.dart
│   │   │   └── providers/
│   │   │       ├── task_list_provider.dart
│   │   │       ├── task_detail_provider.dart
│   │   │       └── task_sync_provider.dart
│   │   │
│   │   ├── inbox/
│   │   │   ├── presentation/
│   │   │   │   ├── inbox_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── quick_add_bar.dart
│   │   │   │       └── inbox_task_tile.dart
│   │   │   └── providers/
│   │   │       └── inbox_provider.dart
│   │   │
│   │   ├── today/
│   │   │   ├── presentation/
│   │   │   │   └── today_screen.dart
│   │   │   └── providers/
│   │   │       └── today_provider.dart
│   │   │
│   │   ├── upcoming/
│   │   │   ├── presentation/
│   │   │   │   └── upcoming_screen.dart
│   │   │   └── providers/
│   │   │       └── upcoming_provider.dart
│   │   │
│   │   ├── settings/
│   │   │   ├── presentation/
│   │   │   │   ├── settings_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── theme_picker.dart
│   │   │   │       └── notification_settings.dart
│   │   │   └── providers/
│   │   │       └── settings_provider.dart
│   │   │
│   │   └── sync/
│   │       ├── data/
│   │       │   └── sync_service.dart
│   │       └── providers/
│   │           └── sync_status_provider.dart
│   │
│   └── shared/
│       ├── widgets/
│       │   ├── loading_indicator.dart
│       │   ├── error_view.dart
│       │   ├── empty_state.dart
│       │   └── bottom_nav.dart
│       └── utils/
│           ├── date_utils.dart
│           └── string_utils.dart
│
├── test/
│   ├── unit/
│   ├── widget/
│   └── integration/
│
├── pubspec.yaml
├── analysis_options.yaml
└── l10n/
    ├── app_en.arb
    └── app_vi.arb           # If needed
```

### 2.2 Key Dependencies

```yaml
# pubspec.yaml
name: flow_tasks
description: Simple AI-powered task management

dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0

  # Navigation
  go_router: ^13.0.0

  # Local Database (Offline-first)
  drift: ^2.15.0
  sqlite3_flutter_libs: ^0.5.0
  path_provider: ^2.1.0
  path: ^1.9.0

  # Networking
  dio: ^5.4.0
  retrofit: ^4.1.0
  json_annotation: ^4.8.0

  # Auth
  flutter_secure_storage: ^9.0.0
  google_sign_in: ^6.2.0
  sign_in_with_apple: ^6.0.0

  # UI
  flutter_animate: ^4.4.0
  shimmer: ^3.0.0
  cached_network_image: ^3.3.0

  # Utilities
  freezed_annotation: ^2.4.0
  intl: ^0.19.0
  uuid: ^4.3.0
  connectivity_plus: ^5.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Code Generation
  build_runner: ^2.4.0
  riverpod_generator: ^2.4.0
  freezed: ^2.4.0
  json_serializable: ^6.7.0
  retrofit_generator: ^8.1.0
  drift_dev: ^2.15.0

  # Testing
  mockito: ^5.4.0
  mocktail: ^1.0.0

  # Linting
  flutter_lints: ^3.0.0
```

### 2.3 Domain Models

```dart
// lib/features/tasks/domain/task.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'task.freezed.dart';
part 'task.g.dart';

@freezed
class Task with _$Task {
  const factory Task({
    required String id,
    required String userId,
    String? parentId,
    String? projectId,
    required String title,
    String? description,
    String? aiSummary,
    @Default([]) List<TaskStep> aiSteps,
    @Default(TaskStatus.pending) TaskStatus status,
    @Default(0) int priority,
    @Default(1) int complexity,
    @Default(0) int depth,
    DateTime? startDate,
    DateTime? dueDate,
    DateTime? completedAt,
    @Default([]) List<String> tags,
    @Default({}) Map<String, dynamic> metadata,

    // Sync
    String? localId,
    @Default(1) int version,
    DateTime? lastSyncedAt,

    // Timestamps
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}

enum TaskStatus {
  pending,
  inProgress,
  completed,
  cancelled,
  archived,
}

@freezed
class TaskStep with _$TaskStep {
  const factory TaskStep({
    required int step,
    required String action,
    @Default(false) bool done,
  }) = _TaskStep;

  factory TaskStep.fromJson(Map<String, dynamic> json) =>
      _$TaskStepFromJson(json);
}
```

### 2.4 Local Database (Drift)

```dart
// packages/flow_database/lib/src/database.dart
import 'package:drift/drift.dart';

part 'database.g.dart';

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get aiSummary => text().nullable()();
  TextColumn get aiSteps => text().map(const JsonListConverter()).nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get complexity => integer().withDefault(const Constant(1))();
  IntColumn get depth => integer().withDefault(const Constant(0))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get tags => text().map(const JsonListConverter()).nullable()();
  TextColumn get metadata => text().map(const JsonMapConverter()).nullable()();

  // Sync tracking
  TextColumn get localId => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(false))();
  TextColumn get syncOperation => text().nullable()(); // create, update, delete

  // Timestamps
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Tasks])
class FlowDatabase extends _$FlowDatabase {
  FlowDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  // Queries
  Stream<List<Task>> watchTasks(String userId) {
    return (select(tasks)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.depth.isSmallerOrEqualValue(1))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<List<Task>> watchTodayTasks(String userId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(tasks)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.dueDate.isBetweenValues(startOfDay, endOfDay))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  Stream<List<Task>> watchChildTasks(String parentId) {
    return (select(tasks)
          ..where((t) => t.parentId.equals(parentId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<TasksCompanion>> getPendingSyncTasks(String userId) {
    return (select(tasks)
          ..where((t) => t.userId.equals(userId))
          ..where((t) => t.pendingSync.equals(true)))
        .get();
  }
}
```

### 2.5 Repository Pattern

```dart
// lib/features/tasks/data/task_repository.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'task_repository.g.dart';

@riverpod
TaskRepository taskRepository(TaskRepositoryRef ref) {
  return TaskRepository(
    localSource: ref.watch(taskLocalSourceProvider),
    remoteSource: ref.watch(taskRemoteSourceProvider),
    syncService: ref.watch(syncServiceProvider),
  );
}

class TaskRepository {
  final TaskLocalSource _localSource;
  final TaskRemoteSource _remoteSource;
  final SyncService _syncService;

  TaskRepository({
    required TaskLocalSource localSource,
    required TaskRemoteSource remoteSource,
    required SyncService syncService,
  })  : _localSource = localSource,
        _remoteSource = remoteSource,
        _syncService = syncService;

  /// Watch all tasks (local-first)
  Stream<List<Task>> watchTasks(String userId) {
    return _localSource.watchTasks(userId);
  }

  /// Watch today's tasks
  Stream<List<Task>> watchTodayTasks(String userId) {
    return _localSource.watchTodayTasks(userId);
  }

  /// Create task (offline-first)
  Future<Task> createTask(TaskCreate request) async {
    // 1. Generate local ID
    final localId = const Uuid().v4();

    // 2. Save to local DB with pending sync flag
    final task = await _localSource.createTask(
      request.copyWith(localId: localId),
      pendingSync: true,
    );

    // 3. Queue for background sync
    _syncService.queueCreate(task);

    return task;
  }

  /// Update task (offline-first)
  Future<Task> updateTask(String id, TaskUpdate request) async {
    // 1. Update local DB
    final task = await _localSource.updateTask(id, request);

    // 2. Queue for background sync
    _syncService.queueUpdate(task);

    return task;
  }

  /// Delete task (offline-first, soft delete)
  Future<void> deleteTask(String id) async {
    // 1. Soft delete locally
    await _localSource.softDeleteTask(id);

    // 2. Queue for background sync
    _syncService.queueDelete(id);
  }

  /// Complete task
  Future<Task> completeTask(String id) async {
    return updateTask(id, TaskUpdate(
      status: TaskStatus.completed,
      completedAt: DateTime.now(),
    ));
  }

  /// Request AI decomposition
  Future<Task> decomposeTask(String id) async {
    final task = await _localSource.getTask(id);
    if (task == null) throw TaskNotFoundException(id);

    // Call API (requires online)
    final decomposed = await _remoteSource.decomposeTask(id);

    // Update local
    await _localSource.updateTask(id, TaskUpdate(
      aiSummary: decomposed.aiSummary,
      aiSteps: decomposed.aiSteps,
      complexity: decomposed.complexity,
    ));

    return decomposed;
  }

  /// Add child task (enforce 2-layer limit)
  Future<Task> addChildTask(String parentId, TaskCreate request) async {
    final parent = await _localSource.getTask(parentId);
    if (parent == null) throw TaskNotFoundException(parentId);

    // Check depth limit
    if (parent.depth >= 1) {
      throw DepthLimitExceededException(
        'Flow Tasks only supports 2 layers. Consider using Flow Projects for complex tasks.',
      );
    }

    return createTask(request.copyWith(
      parentId: parentId,
      depth: parent.depth + 1,
    ));
  }
}
```

### 2.6 State Management (Riverpod)

```dart
// lib/features/tasks/providers/task_list_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'task_list_provider.g.dart';

@riverpod
class TaskListNotifier extends _$TaskListNotifier {
  @override
  Stream<List<Task>> build() {
    final userId = ref.watch(currentUserProvider).requireValue.id;
    return ref.watch(taskRepositoryProvider).watchTasks(userId);
  }

  Future<void> createTask(String title) async {
    final userId = ref.read(currentUserProvider).requireValue.id;
    await ref.read(taskRepositoryProvider).createTask(TaskCreate(
      userId: userId,
      title: title,
    ));
  }

  Future<void> completeTask(String id) async {
    await ref.read(taskRepositoryProvider).completeTask(id);
  }

  Future<void> deleteTask(String id) async {
    await ref.read(taskRepositoryProvider).deleteTask(id);
  }
}

@riverpod
Stream<List<Task>> todayTasks(TodayTasksRef ref) {
  final userId = ref.watch(currentUserProvider).requireValue.id;
  return ref.watch(taskRepositoryProvider).watchTodayTasks(userId);
}

@riverpod
Stream<List<Task>> upcomingTasks(UpcomingTasksRef ref) {
  final userId = ref.watch(currentUserProvider).requireValue.id;
  return ref.watch(taskRepositoryProvider).watchUpcomingTasks(userId);
}

@riverpod
class TaskDetailNotifier extends _$TaskDetailNotifier {
  @override
  Future<Task?> build(String taskId) async {
    return ref.watch(taskRepositoryProvider).watchTask(taskId).first;
  }

  Future<void> update(TaskUpdate request) async {
    await ref.read(taskRepositoryProvider).updateTask(state.value!.id, request);
  }

  Future<void> decompose() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(taskRepositoryProvider).decomposeTask(state.value!.id));
  }

  Future<void> toggleStep(int stepIndex) async {
    final task = state.value!;
    final steps = [...task.aiSteps];
    steps[stepIndex] = steps[stepIndex].copyWith(
      done: !steps[stepIndex].done,
    );
    await update(TaskUpdate(aiSteps: steps));
  }
}
```

---

## 3. Screen Designs

### 3.1 Main Task List Screen

```dart
// lib/features/tasks/presentation/screens/task_list_screen.dart

class TaskListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListNotifierProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with search
          SliverAppBar(
            floating: true,
            title: const Text('Tasks'),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _showSearch(context),
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: () => _showFilters(context),
              ),
            ],
          ),

          // Quick Add Bar (always visible)
          SliverPersistentHeader(
            pinned: true,
            delegate: QuickAddBarDelegate(
              onSubmit: (title) => ref
                  .read(taskListNotifierProvider.notifier)
                  .createTask(title),
            ),
          ),

          // Task List
          tasksAsync.when(
            data: (tasks) => _buildTaskList(tasks, ref),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: ErrorView(error: e),
            ),
          ),
        ],
      ),

      // Bottom Navigation
      bottomNavigationBar: const FlowBottomNav(currentIndex: 0),
    );
  }

  Widget _buildTaskList(List<Task> tasks, WidgetRef ref) {
    if (tasks.isEmpty) {
      return SliverFillRemaining(
        child: EmptyState(
          icon: Icons.check_circle_outline,
          title: 'No tasks yet',
          subtitle: 'Add your first task above',
        ),
      );
    }

    // Group by parent (show parents with their children)
    final parentTasks = tasks.where((t) => t.parentId == null).toList();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final task = parentTasks[index];
          final children = tasks.where((t) => t.parentId == task.id).toList();

          return TaskTile(
            task: task,
            children: children,
            onTap: () => _openTaskDetail(context, task.id),
            onComplete: () => ref
                .read(taskListNotifierProvider.notifier)
                .completeTask(task.id),
            onDelete: () => ref
                .read(taskListNotifierProvider.notifier)
                .deleteTask(task.id),
          );
        },
        childCount: parentTasks.length,
      ),
    );
  }
}
```

### 3.2 Task Tile Widget

```dart
// lib/features/tasks/presentation/widgets/task_tile.dart

class TaskTile extends StatelessWidget {
  final Task task;
  final List<Task> children;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const TaskTile({
    required this.task,
    required this.children,
    required this.onTap,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Column(
        children: [
          // Parent task
          ListTile(
            leading: Checkbox(
              value: task.status == TaskStatus.completed,
              onChanged: (_) => onComplete(),
            ),
            title: Text(
              task.aiSummary ?? task.title,
              style: TextStyle(
                decoration: task.status == TaskStatus.completed
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            subtitle: _buildSubtitle(),
            trailing: _buildTrailing(context),
            onTap: onTap,
          ),

          // Child tasks (if any)
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                children: children.map((child) => _buildChildTile(child)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildSubtitle() {
    final parts = <String>[];

    if (task.dueDate != null) {
      parts.add(DateFormat('MMM d').format(task.dueDate!));
    }

    if (task.aiSteps.isNotEmpty) {
      final done = task.aiSteps.where((s) => s.done).length;
      parts.add('${done}/${task.aiSteps.length} steps');
    }

    if (parts.isEmpty) return null;
    return Text(parts.join(' · '));
  }

  Widget _buildTrailing(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Priority indicator
        if (task.priority > 0)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _priorityColor(task.priority),
            ),
          ),

        // Complexity badge (if high)
        if (task.complexity >= 7)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Chip(
              label: const Text('Complex'),
              labelStyle: const TextStyle(fontSize: 10),
              backgroundColor: Colors.orange.shade100,
              padding: EdgeInsets.zero,
            ),
          ),

        // Expand indicator if has children
        if (children.isNotEmpty)
          const Icon(Icons.expand_more),
      ],
    );
  }

  Widget _buildChildTile(Task child) {
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: child.status == TaskStatus.completed,
        onChanged: (_) {}, // TODO: complete child
      ),
      title: Text(
        child.aiSummary ?? child.title,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Color _priorityColor(int priority) {
    switch (priority) {
      case 4: return Colors.red;
      case 3: return Colors.orange;
      case 2: return Colors.yellow.shade700;
      default: return Colors.grey;
    }
  }
}
```

### 3.3 Task Detail Screen

```dart
// lib/features/tasks/presentation/screens/task_detail_screen.dart

class TaskDetailScreen extends ConsumerWidget {
  final String taskId;

  const TaskDetailScreen({required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskDetailNotifierProvider(taskId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: 'AI Decompose',
            onPressed: () => ref
                .read(taskDetailNotifierProvider(taskId).notifier)
                .decompose(),
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                value: 'convert',
                child: Text('Convert to Project'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
            onSelected: (value) => _handleMenuAction(context, ref, value),
          ),
        ],
      ),
      body: taskAsync.when(
        data: (task) => task == null
            ? const Center(child: Text('Task not found'))
            : _buildContent(context, ref, task),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Task task) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            task.aiSummary ?? task.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),

          const SizedBox(height: 8),

          // Original description (if different from AI summary)
          if (task.description != null && task.description != task.aiSummary)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Original',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(task.description!),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Status & Priority Row
          Row(
            children: [
              _buildStatusChip(task.status),
              const SizedBox(width: 8),
              _buildPriorityChip(task.priority),
              const Spacer(),
              if (task.complexity >= 7)
                Chip(
                  label: Text('Complexity: ${task.complexity}/10'),
                  backgroundColor: Colors.orange.shade100,
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Due Date
          if (task.dueDate != null)
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(DateFormat('EEEE, MMM d, yyyy').format(task.dueDate!)),
              trailing: TextButton(
                child: const Text('Change'),
                onPressed: () => _showDatePicker(context, ref, task),
              ),
            ),

          const SizedBox(height: 16),

          // AI Steps (How-to)
          if (task.aiSteps.isNotEmpty) ...[
            Text(
              'Steps',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...task.aiSteps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              return CheckboxListTile(
                value: step.done,
                onChanged: (_) => ref
                    .read(taskDetailNotifierProvider(taskId).notifier)
                    .toggleStep(index),
                title: Text(step.action),
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
          ],

          const SizedBox(height: 16),

          // Add Sub-task Button
          if (task.depth == 0)
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Sub-task'),
              onPressed: () => _showAddSubtask(context, ref, task.id),
            ),

          // Convert to Project Banner (if complex)
          if (task.complexity >= 7) ...[
            const SizedBox(height: 24),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'This task seems complex',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Consider converting it to a Project in Flow Projects '
                      'for better organization with dependencies and timelines.',
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      child: const Text('Convert to Project'),
                      onPressed: () => _convertToProject(context, ref, task),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

---

## 4. Navigation Structure

```
Flow Tasks App
│
├── Main View (Two Tabs)
│   ├── [Personal] ← Default tab
│   │   ├── Inbox (all personal tasks)
│   │   ├── Today (personal tasks due today)
│   │   └── Upcoming (personal tasks with future dates)
│   │
│   └── [Assigned to Me]
│       └── Tasks assigned to you in any project
│       └── Grouped by project
│       └── Tap → Opens in Flow Projects app
│       └── Can mark complete (syncs to projects_db)
│
├── Task Detail
│   ├── View/edit personal task
│   ├── AI decomposition
│   ├── "Add to Project" button → Promotion flow
│   └── Linked indicator (if promoted but kept)
│
├── Completed
│   └── Archived completed tasks
│
└── Settings
    ├── Account
    ├── Theme
    ├── Notifications
    └── Sync Status
```

### 4.0 Two-Tab UI Design

```
┌─────────────────────────────────────────────────────────────────┐
│ Flow Tasks                                              ⚙️      │
├─────────────────────────────────────────────────────────────────┤
│  [Personal]  [Assigned to Me]                                   │
│      ↑            ↑                                             │
│    active       reads from projects_db                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  + Add task...                                                  │
│  ───────────────────────────────────────────────────────────── │
│                                                                 │
│  ○ Fix bathroom leak                              📅 Today      │
│    └─ ○ Call plumber                                           │
│    └─ ○ Buy supplies                                           │
│                                                                 │
│  ● Prepare Q3 presentation                        🔗 Linked     │
│    ↳ In: Project Beta                             ↗            │
│                                                                 │
│  ○ Email John about proposal                      📅 Tomorrow   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Legend:
  ○     = Uncompleted task
  ●     = Completed task
  🔗    = Linked to project (personal copy retained after promotion)
  ↗     = Tap to open in Flow Projects app
```

### 4.0.1 "Assigned to Me" Tab

```
┌─────────────────────────────────────────────────────────────────┐
│ Flow Tasks                                              ⚙️      │
├─────────────────────────────────────────────────────────────────┤
│  [Personal]  [Assigned to Me]                                   │
│                    ↑ active                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PROJECT ALPHA                                                  │
│  ─────────────────────────────────────────────────────────────  │
│  ○ Review PR #123                                 📅 Today  ↗  │
│  ○ Update API documentation                       📅 Jan 20 ↗  │
│                                                                 │
│  PROJECT BETA                                                   │
│  ─────────────────────────────────────────────────────────────  │
│  ○ Design mockups for new feature                 📅 Jan 18 ↗  │
│                                                                 │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ℹ️  These tasks are from your projects.                 │   │
│  │     Tap any task to view details in Flow Projects.      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.0.2 Promotion Flow (Personal → Project)

```
User taps "Add to Project" on personal task
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                    Add to Project                                  │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ 📋  Fix bathroom leak                                        │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  Select project                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ ▼  Project Beta                                              │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  Add under (optional)                                             │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ ▼  1.0 Planning > 1.1 Research                              │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ─────────────────────────────────────────────────────────────── │
│  □ Keep in my personal tasks                                      │
│    ↑ Unchecked by default                                        │
│  ─────────────────────────────────────────────────────────────── │
│                                                                   │
│                              [Cancel]  [Add to Project]           │
└───────────────────────────────────────────────────────────────────┘
                    │
                    ▼
          ┌─────────┴─────────┐
          │                   │
    Keep checked?        Keep unchecked? (default)
          │                   │
          ▼                   ▼
    ┌───────────────┐   ┌───────────────┐
    │ Personal task │   │ Personal task │
    │ KEPT with     │   │ DELETED       │
    │ "linked" badge│   │               │
    └───────────────┘   └───────────────┘
          │                   │
          └─────────┬─────────┘
                    │
                    ▼
          ┌───────────────────┐
          │ WBS node created  │
          │ in projects_db    │
          │ source_task_id    │
          │ points to original│
          └───────────────────┘
```

**API Call:**
```
POST /api/v1/tasks/{id}/promote
{
  "project_id": "uuid",
  "parent_node_id": "uuid | null",
  "keep_personal": false
}
```

**Response:**
```json
{
  "wbs_node": { "id": "...", "title": "...", ... },
  "personal_task": null,  // or updated task if keep_personal=true
  "message": "Task added to project"
}
```

### 4.0.3 Linked Task Indicator

When a personal task is promoted but kept (`keep_personal: true`), it shows a "linked" badge:

```dart
// Linked task appears in Personal tab like this:
┌─────────────────────────────────────────────────────────────────┐
│  ○ Prepare Q3 presentation                        📅 Today      │
│    ┌──────────────────────────────────────────┐                │
│    │ 🔗 In: Project Beta                   ↗ │                │
│    └──────────────────────────────────────────┘                │
│    Tap badge to open in Flow Projects                          │
└─────────────────────────────────────────────────────────────────┘
```

**Important:** Linked tasks are **NOT synced**. They are independent copies. The link is informational only ("this task originated from that personal task").

### 4.1 Router Configuration

```dart
// lib/core/router/app_router.dart

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/inbox',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/inbox';
      return null;
    },
    routes: [
      // Auth routes
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, __) => const RegisterScreen(),
      ),

      // Main shell with bottom nav
      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/inbox',
            builder: (_, __) => const InboxScreen(),
          ),
          GoRoute(
            path: '/today',
            builder: (_, __) => const TodayScreen(),
          ),
          GoRoute(
            path: '/upcoming',
            builder: (_, __) => const UpcomingScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),

      // Task detail (modal/push)
      GoRoute(
        path: '/task/:id',
        builder: (_, state) => TaskDetailScreen(
          taskId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});
```

---

## 5. Sync Strategy

### 5.1 Offline Queue

```dart
// lib/features/sync/data/sync_service.dart

class SyncService {
  final FlowDatabase _db;
  final FlowApiClient _api;
  final ConnectivityService _connectivity;

  Timer? _syncTimer;

  void startBackgroundSync() {
    // Sync every 30 seconds when online
    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _attemptSync(),
    );

    // Also sync on connectivity change
    _connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) _attemptSync();
    });
  }

  Future<void> _attemptSync() async {
    if (!await _connectivity.isOnline) return;

    try {
      // 1. Push local changes
      await _pushPendingChanges();

      // 2. Pull remote changes
      await _pullRemoteChanges();
    } catch (e) {
      // Log error, will retry on next interval
      debugPrint('Sync failed: $e');
    }
  }

  Future<void> _pushPendingChanges() async {
    final pending = await _db.getPendingSyncTasks();

    for (final task in pending) {
      final operation = task.syncOperation.value;

      switch (operation) {
        case 'create':
          final remote = await _api.createTask(task.toTaskCreate());
          await _db.updateTaskServerId(task.localId.value!, remote.id);
          break;
        case 'update':
          await _api.updateTask(task.id.value, task.toTaskUpdate());
          break;
        case 'delete':
          await _api.deleteTask(task.id.value);
          break;
      }

      // Mark as synced
      await _db.markTaskSynced(task.id.value);
    }
  }

  Future<void> _pullRemoteChanges() async {
    final lastSync = await _db.getLastSyncTimestamp();
    final changes = await _api.pullChanges(since: lastSync);

    for (final change in changes) {
      await _db.applyRemoteChange(change);
    }

    await _db.setLastSyncTimestamp(DateTime.now());
  }
}
```

### 5.2 Conflict Resolution

```dart
// Simple Last-Write-Wins for Flow Tasks
enum ConflictResolution {
  clientWins,  // Local changes take precedence
  serverWins,  // Server changes take precedence
  merge,       // Attempt to merge (for arrays like tags)
}

class ConflictResolver {
  ConflictResolution resolve(Task local, Task remote) {
    // If local is newer, client wins
    if (local.updatedAt.isAfter(remote.updatedAt)) {
      return ConflictResolution.clientWins;
    }

    // If remote is newer but local has pending changes, merge
    if (local.pendingSync) {
      return ConflictResolution.merge;
    }

    // Otherwise server wins
    return ConflictResolution.serverWins;
  }

  Task merge(Task local, Task remote) {
    // Take remote's base, but keep local's pending changes
    return remote.copyWith(
      title: local.pendingSync ? local.title : remote.title,
      status: local.pendingSync ? local.status : remote.status,
      tags: {...local.tags, ...remote.tags}.toList(),
    );
  }
}
```

---

## 6. AI Integration Points

### 6.1 On Task Create

```dart
// When user creates a task, queue AI processing
Future<Task> createTask(TaskCreate request) async {
  final task = await _localSource.createTask(request);

  // Queue background AI processing
  ref.read(aiServiceProvider).queueTaskProcessing(task.id, [
    AiTask.cleanDescription,
    AiTask.extractEntities,
    AiTask.assessComplexity,
  ]);

  return task;
}
```

### 6.2 On Decompose Request

```dart
// User taps "Break down" button
Future<void> decomposeTask(String taskId) async {
  // Show loading
  state = const AsyncLoading();

  // Call API
  final result = await _api.decomposeTask(taskId);

  // Update local with AI results
  await _db.updateTask(taskId, TasksCompanion(
    aiSummary: Value(result.summary),
    aiSteps: Value(jsonEncode(result.steps)),
    complexity: Value(result.complexity),
  ));

  // Refresh state
  ref.invalidateSelf();
}
```

---

## 7. Testing Strategy

### 7.1 Unit Tests
- Repository logic
- Domain model validation
- Sync conflict resolution

### 7.2 Widget Tests
- Task tile rendering
- Quick add bar input
- Checkbox state changes

### 7.3 Integration Tests
- Full task CRUD flow
- Offline → Online sync
- OAuth flow

---

## 8. Launch Checklist

- [ ] Core task CRUD working
- [ ] Offline support functional
- [ ] AI decomposition integrated
- [ ] OAuth (Google, Apple, Microsoft)
- [ ] Today/Upcoming views
- [ ] Settings screen
- [ ] Push notifications
- [ ] App Store/Play Store assets
- [ ] Privacy policy
- [ ] Terms of service

---

## Next: See flow-projects.md for the PM app plan.
