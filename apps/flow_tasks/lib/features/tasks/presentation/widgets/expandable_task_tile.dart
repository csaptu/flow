import 'package:flutter/material.dart';
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
class ExpandableTaskTile extends ConsumerStatefulWidget {
  final Task task;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;
  final VoidCallback? onDelete;

  const ExpandableTaskTile({
    super.key,
    required this.task,
    required this.onComplete,
    required this.onUncomplete,
    this.onDelete,
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
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: isSelected ? colors.sidebarSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                ref.read(isNewlyCreatedTaskProvider.notifier).state = false;
                ref.read(selectedTaskIdProvider.notifier).state = task.id;
              },
              borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
              child: Padding(
                padding: FlowSpacing.listItemPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
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

                    // Date on the right
                    if (task.dueDate != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          _formatDate(task.dueDate!),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _isToday(task.dueDate!) ? FontWeight.w600 : FontWeight.w400,
                            color: task.isOverdue ? colors.error : colors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
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

  Widget _buildContent(FlowColorScheme colors, bool isCompleted) {
    final task = widget.task;
    final displayTitle = removeHashtags(task.aiSummary ?? task.title);
    final showStrikethrough = isCompleted || _isAnimatingCompletion;

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
    final cleaned = removeHashtags(description).trim();
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

  String _formatDate(DateTime date) {
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
