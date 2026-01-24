import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/hashtag_text.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/rich_description_text.dart';
import 'package:intl/intl.dart';

/// Task tile that opens side panel on click (like TickTick)
/// Supports drag-and-drop to make tasks into subtasks
class ExpandableTaskTile extends ConsumerStatefulWidget {
  final Task task;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;
  final VoidCallback? onDelete;
  final Function(Task draggedTask, Task targetTask)? onDropInto;

  const ExpandableTaskTile({
    super.key,
    required this.task,
    required this.onComplete,
    required this.onUncomplete,
    this.onDelete,
    this.onDropInto,
  });

  @override
  ConsumerState<ExpandableTaskTile> createState() => _ExpandableTaskTileState();
}

class _ExpandableTaskTileState extends ConsumerState<ExpandableTaskTile>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _strikethroughController;
  late AnimationController _flyAwayController;

  // Animations
  late Animation<double> _strikethroughAnimation;
  late Animation<Offset> _flyAwayAnimation;
  late Animation<double> _fadeAnimation;

  bool _isAnimatingCompletion = false;
  bool _isDragTarget = false; // Highlight when another task is dragged over
  bool _isDragging = false; // Track when this tile is being dragged

  @override
  void initState() {
    super.initState();

    // Strikethrough: 0.5s
    _strikethroughController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _strikethroughAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _strikethroughController, curve: Curves.easeInOut),
    );

    // Fly away: 0.5s
    _flyAwayController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flyAwayAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 2), // Fly down 2x the widget height
    ).animate(CurvedAnimation(parent: _flyAwayController, curve: Curves.easeInCubic));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _flyAwayController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _strikethroughController.dispose();
    _flyAwayController.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (_isAnimatingCompletion) return;

    setState(() => _isAnimatingCompletion = true);

    // 1. Strikethrough animation (0.5s)
    await _strikethroughController.forward();

    // 2. Wait (0.5s)
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. Fly away animation (0.5s)
    await _flyAwayController.forward();

    // 4. Actually complete the task
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final task = widget.task;
    final isCompleted = task.isCompleted;
    final isSelected = ref.watch(selectedTaskIdProvider) == task.id;

    Widget tile = SlideTransition(
      position: _flyAwayAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: DragTarget<Task>(
          onWillAcceptWithDetails: (details) {
            final draggedTask = details.data;
            // Can accept if:
            // - Not dropping on itself
            // - This task is a root task (depth 0)
            // - Dragged task has no children (can become a subtask)
            // - This task has no children yet (for simplicity)
            final canAccept = draggedTask.id != task.id &&
                task.depth == 0 &&
                draggedTask.childrenCount == 0;
            if (canAccept && !_isDragTarget) {
              setState(() => _isDragTarget = true);
            }
            return canAccept;
          },
          onLeave: (_) {
            if (_isDragTarget) {
              setState(() => _isDragTarget = false);
            }
          },
          onAcceptWithDetails: (details) {
            setState(() => _isDragTarget = false);
            widget.onDropInto?.call(details.data, task);
          },
          builder: (context, candidateData, rejectedData) {
            return Container(
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: _isDragTarget
                    ? colors.primary.withAlpha(40)
                    : (isSelected ? colors.sidebarSelected : Colors.transparent),
                borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                border: _isDragTarget
                    ? Border.all(color: colors.primary, width: 2)
                    : null,
              ),
              child: LongPressDraggable<Task>(
                data: task,
                delay: const Duration(milliseconds: 150),
                onDragStarted: () => setState(() => _isDragging = true),
                onDragEnd: (_) => setState(() => _isDragging = false),
                onDraggableCanceled: (_, __) => setState(() => _isDragging = false),
                feedback: Material(
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.4,
                  child: _buildTileContent(colors, task, isCompleted, isSelected),
                ),
                child: _buildTileContent(colors, task, isCompleted, isSelected),
              ),
            );
          },
        ),
      ),
    );

    // Wrap with Dismissible for swipe-to-trash
    if (widget.onDelete != null && !_isAnimatingCompletion) {
      tile = Dismissible(
        key: Key('task_${task.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => widget.onDelete!(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: colors.error,
          child: const Icon(
            Icons.delete_outline,
            color: Colors.white,
          ),
        ),
        child: tile,
      );
    }

    return tile;
  }

  /// Build the main tile content (used in draggable and non-draggable states)
  Widget _buildTileContent(FlowColorScheme colors, Task task, bool isCompleted, bool isSelected) {
    // Use GestureDetector instead of InkWell for precise mobile touch handling
    // The selection highlight is handled by the parent Container, not InkWell ripple
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // Ensures tap is captured within bounds
      onTap: () {
        ref.read(isNewlyCreatedTaskProvider.notifier).state = false;
        ref.read(selectedTaskIdProvider.notifier).state = task.id;
      },
      child: Padding(
        padding: FlowSpacing.listItemPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Drag handle (only visible when dragging)
            if (_isDragging) ...[
              Icon(
                Icons.drag_indicator,
                size: 18,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 4),
            ],

            // Checkbox
            _BearCheckbox(
              isChecked: isCompleted || _isAnimatingCompletion,
              onTap: isCompleted ? widget.onUncomplete : _handleComplete,
              priority: task.priority.value,
            ),
            const SizedBox(width: 12),

            // Content with animated strikethrough
            Expanded(
              child: _buildContent(colors, isCompleted),
            ),

            // Subtask count indicator
            if (task.childrenCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${task.childrenCount}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

            // Date on the right
            if (task.dueAt != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _formatDate(task.dueAt!, task.hasDueTime),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: task.isOverdue ? FontWeight.w700 : (_isToday(task.dueAt!) ? FontWeight.w600 : FontWeight.w400),
                    color: task.isOverdue ? colors.error : colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(FlowColorScheme colors, bool isCompleted) {
    final task = widget.task;
    final displayTitle = removeHashtags(task.displayTitle);
    final showStrikethrough = isCompleted || _isAnimatingCompletion;
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title with animated strikethrough
        AnimatedBuilder(
          animation: _strikethroughAnimation,
          builder: (context, child) {
            return _AnimatedStrikethroughText(
              text: displayTitle.isEmpty ? task.title : displayTitle,
              progress: _isAnimatingCompletion ? _strikethroughAnimation.value : (isCompleted ? 1.0 : 0.0),
              style: TextStyle(
                fontSize: 16,
                fontWeight: showStrikethrough ? FontWeight.w400 : FontWeight.w500,
                color: showStrikethrough ? colors.textTertiary : colors.textPrimary,
              ),
              strikeColor: colors.textTertiary,
            );
          },
        ),

        // Metadata row
        if (_hasMetadata) ...[
          const SizedBox(height: 4),
          _buildMetadataRow(colors),
        ],

      ],
    );
  }

  Widget _buildEntityChips(FlowColorScheme colors) {
    final task = widget.task;
    // Show up to 3 entities in compact mode - only person, location, place, organization
    final validTypes = {'person', 'location', 'place', 'organization'};
    final displayEntities = task.entities
        .where((e) => validTypes.contains(e.type))
        .take(3)
        .toList();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: displayEntities.map((entity) {
        return _CompactEntityChip(
          entity: entity,
          onTap: () => _navigateToSmartList(entity),
        );
      }).toList(),
    );
  }

  void _navigateToSmartList(AIEntity entity) {
    ref.read(selectedSmartListProvider.notifier).state = (type: entity.type, value: entity.value);
    ref.read(selectedSidebarIndexProvider.notifier).state = 200;
    ref.read(selectedListIdProvider.notifier).state = null;
  }

  Widget _buildAdminIdRow(FlowColorScheme colors, Task task) {
    // Show first 8 chars of ID for brevity
    final shortId = task.id.length > 8 ? task.id.substring(0, 8) : task.id;
    // Show due date timestamp for debugging
    final dueDateStr = task.dueAt != null
        ? ' | due: ${task.dueAt!.toIso8601String()}'
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '$shortId$dueDateStr',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: colors.textTertiary.withOpacity(0.7),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: task.id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied: ${task.id}'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Icon(
            Icons.copy_rounded,
            size: 12,
            color: colors.textTertiary.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  bool get _hasMetadata =>
      widget.task.description != null && widget.task.description!.isNotEmpty;

  Widget _buildMetadataRow(FlowColorScheme colors) {
    final task = widget.task;
    final widgets = <Widget>[];

    if (task.description != null && task.description!.isNotEmpty) {
      final descriptionPreview = _getDescriptionPreview(task.description!);
      if (descriptionPreview.isNotEmpty) {
        widgets.add(RichDescriptionText(
          text: descriptionPreview,
          style: TextStyle(
            fontSize: 13,
            color: colors.textSecondary,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  String _getDescriptionPreview(String description) {
    // Remove hashtags and image tags [img1], [img2], etc.
    var cleaned = removeHashtags(description).trim();
    cleaned = cleaned.replaceAll(RegExp(r'\[img\d+\]'), '').trim();
    if (cleaned.isEmpty) return '';
    final lines = cleaned.split('\n').take(2).join(' ').trim();
    if (lines.length > 120) {
      return '${lines.substring(0, 117)}...';
    }
    return lines;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly == today;
  }

  /// Format due date for task list display (date only, no time)
  /// Time is still used for sorting but not displayed in the list view
  String _formatDate(DateTime date, bool hasDueTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      // All other dates: "Jan 15" format
      return DateFormat('MMM d').format(date);
    }
  }
}

/// Custom widget that draws strikethrough progressively from left to right
class _AnimatedStrikethroughText extends StatelessWidget {
  final String text;
  final double progress; // 0.0 to 1.0
  final TextStyle style;
  final Color strikeColor;

  const _AnimatedStrikethroughText({
    required this.text,
    required this.progress,
    required this.style,
    required this.strikeColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _StrikethroughPainter(
        progress: progress,
        color: strikeColor,
        textStyle: style,
        text: text,
      ),
      child: Text(
        text,
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _StrikethroughPainter extends CustomPainter {
  final double progress;
  final Color color;
  final TextStyle textStyle;
  final String text;

  _StrikethroughPainter({
    required this.progress,
    required this.color,
    required this.textStyle,
    required this.text,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw line from left to right based on progress
    final y = size.height / 2;
    final endX = size.width * progress;

    canvas.drawLine(Offset(0, y), Offset(endX, y), paint);
  }

  @override
  bool shouldRepaint(_StrikethroughPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Bear-style checkbox
class _BearCheckbox extends StatelessWidget {
  final bool isChecked;
  final VoidCallback onTap;
  final int priority;

  const _BearCheckbox({
    required this.isChecked,
    required this.onTap,
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final priorityColor = FlowColors.getPriorityColor(priority);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Stop event from bubbling to parent InkWell
        onTap();
      },
      child: Padding(
        // Larger tap area
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isChecked ? colors.primary : Colors.transparent,
            border: Border.all(
              color: isChecked
                  ? colors.primary
                  : (priorityColor != Colors.transparent ? priorityColor : colors.border),
              width: isChecked ? 0 : 1.5,
            ),
          ),
          child: isChecked
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// Compact entity chip for task list view
class _CompactEntityChip extends StatelessWidget {
  final AIEntity entity;
  final VoidCallback onTap;

  const _CompactEntityChip({
    required this.entity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final chipColors = _getEntityColors(entity.type, colors);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: chipColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: chipColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chipColors.icon, size: 10, color: chipColors.foreground),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                entity.value,
                style: TextStyle(
                  fontSize: 11,
                  color: chipColors.foreground,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _EntityChipColors _getEntityColors(String type, FlowColorScheme colors) {
    switch (type) {
      case 'person':
        return _EntityChipColors(
          background: const Color(0xFF3B82F6).withOpacity(0.1),
          foreground: const Color(0xFF3B82F6),
          border: const Color(0xFF3B82F6).withOpacity(0.3),
          icon: Icons.person_outline,
        );
      case 'location':
      case 'place': // Normalize place to location
        return _EntityChipColors(
          background: const Color(0xFF10B981).withOpacity(0.1),
          foreground: const Color(0xFF10B981),
          border: const Color(0xFF10B981).withOpacity(0.3),
          icon: Icons.place, // Google Maps-like icon
        );
      case 'organization':
        return _EntityChipColors(
          background: const Color(0xFF8B5CF6).withOpacity(0.1),
          foreground: const Color(0xFF8B5CF6),
          border: const Color(0xFF8B5CF6).withOpacity(0.3),
          icon: Icons.business_outlined,
        );
      default:
        return _EntityChipColors(
          background: colors.textTertiary.withOpacity(0.1),
          foreground: colors.textSecondary,
          border: colors.textTertiary.withOpacity(0.3),
          icon: Icons.label_outline,
        );
    }
  }
}

class _EntityChipColors {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  const _EntityChipColors({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });
}
