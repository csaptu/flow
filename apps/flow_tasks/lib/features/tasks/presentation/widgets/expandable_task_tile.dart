import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/hashtag_text.dart';
import 'package:intl/intl.dart';

/// Task tile that opens side panel on click (like TickTick)
class ExpandableTaskTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final isCompleted = task.isCompleted;
    final isSelected = ref.watch(selectedTaskIdProvider) == task.id;

    Widget tile = Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isSelected ? colors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Open side panel
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
                  isChecked: isCompleted,
                  onTap: isCompleted ? onUncomplete : onComplete,
                  priority: task.priority.value,
                ),
                const SizedBox(width: 12),

                // Content
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
    );

    // Wrap with Dismissible for swipe-to-trash
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

  Widget _buildContent(FlowColorScheme colors, bool isCompleted) {
    // Remove hashtags from display title
    final displayTitle = removeHashtags(task.aiSummary ?? task.title);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title without hashtags
        Text(
          displayTitle.isEmpty ? task.title : displayTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isCompleted ? FontWeight.w400 : FontWeight.w500,
            color: isCompleted ? colors.textTertiary : colors.textPrimary,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
            decorationColor: colors.textTertiary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        // Metadata row
        if (_hasMetadata) ...[
          const SizedBox(height: 4),
          _buildMetadataRow(colors),
        ],
      ],
    );
  }

  bool get _hasMetadata => task.groupName != null;

  Widget _buildMetadataRow(FlowColorScheme colors) {
    final parts = <Widget>[];

    // List name (from hashtag)
    if (task.groupName != null) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tag,
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

    return Wrap(spacing: 12, children: parts);
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
    } else if (dateOnly.difference(today).inDays.abs() < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM d').format(date);
    }
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
                : (priorityColor != Colors.transparent ? priorityColor : colors.border),
            width: isChecked ? 0 : 1.5,
          ),
        ),
        child: isChecked
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}
