import 'package:flutter/material.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;
  final VoidCallback? onDelete;

  const TaskTile({
    super.key,
    required this.task,
    required this.onTap,
    required this.onComplete,
    required this.onUncomplete,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isCompleted = task.isCompleted;

    Widget tile = Container(
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
                  onTap: isCompleted ? onUncomplete : onComplete,
                  priority: task.priority.value,
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isCompleted ? FontWeight.w400 : FontWeight.w500,
                          color: isCompleted ? colors.textTertiary : colors.textPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          decorationColor: colors.textTertiary,
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
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.textTertiary,
                    ),
                    onPressed: () {
                      // TODO: Expand children
                    },
                    splashRadius: 16,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Wrap with Dismissible for swipe-to-delete
    if (onDelete != null) {
      tile = Dismissible(
        key: Key('task_${task.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete!(),
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

  // Always show metadata row since we show createdAt when no dueDate
  bool get _hasMetadata => true;

  Widget _buildMetadataRow(BuildContext context) {
    final colors = context.flowColors;
    final parts = <Widget>[];

    // Due date or created date
    if (task.dueDate != null) {
      final isOverdue = task.isOverdue;
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
            style: TextStyle(
              fontSize: 12,
              color: isOverdue ? colors.error : colors.textTertiary,
            ),
          ),
        ],
      ));
    } else {
      // Show created date when no due date
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_rounded,
            size: 12,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            _formatDate(task.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: colors.textTertiary,
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
            style: TextStyle(
              fontSize: 12,
              color: colors.textTertiary,
            ),
          ),
        ],
      ));
    }

    // Group name
    if (task.groupName != null) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 12,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            task.groupName!,
            style: TextStyle(
              fontSize: 12,
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
    } else if (dateOnly.difference(today).inDays.abs() < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
  }
}

/// Bear-style checkbox: minimal circle with soft animation
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
            color: isChecked
                ? colors.primary
                : (priorityColor != Colors.transparent
                    ? priorityColor
                    : colors.border),
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
}
