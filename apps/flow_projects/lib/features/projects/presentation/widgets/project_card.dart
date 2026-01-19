import 'package:flutter/material.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final statusColor = FlowColors.getStatusColor(project.status.name);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: FlowSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status
              Row(
                children: [
                  // Status indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatStatus(project.status),
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  // More options
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz,
                      size: 20,
                      color: colors.textTertiary,
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'archive',
                        child: Row(
                          children: [
                            Icon(Icons.archive_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Archive'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      // TODO: Handle menu actions
                    },
                  ),
                ],
              ),

              const SizedBox(height: FlowSpacing.sm),

              // Title
              Text(
                project.name,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              if (project.description != null && project.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  project.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const Spacer(),

              // Progress bar
              _ProgressIndicator(progress: project.progress.percentage / 100.0),

              const SizedBox(height: FlowSpacing.sm),

              // Footer
              Row(
                children: [
                  // Date range
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDateRange(project.startDate, project.targetDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  // Team members
                  if (project.memberCount > 1)
                    _TeamAvatars(memberCount: project.memberCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStatus(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.planning:
        return 'Planning';
      case ProjectStatus.active:
        return 'Active';
      case ProjectStatus.completed:
        return 'Completed';
      case ProjectStatus.onHold:
        return 'On Hold';
      case ProjectStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    final dateFormat = DateFormat('MMM d');
    if (start == null && end == null) {
      return 'No dates set';
    }
    if (start != null && end != null) {
      return '${dateFormat.format(start)} - ${dateFormat.format(end)}';
    }
    if (start != null) {
      return 'From ${dateFormat.format(start)}';
    }
    return 'Until ${dateFormat.format(end!)}';
  }
}

class _ProgressIndicator extends StatelessWidget {
  final double progress;

  const _ProgressIndicator({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final percentage = (progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 12,
                color: colors.textTertiary,
              ),
            ),
            Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: colors.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0 ? FlowColors.success : colors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _TeamAvatars extends StatelessWidget {
  final int memberCount;

  const _TeamAvatars({required this.memberCount});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final displayCount = memberCount > 3 ? 3 : memberCount;
    final extraCount = memberCount - 3;

    return Row(
      children: [
        // Stacked avatars
        SizedBox(
          width: 20.0 * displayCount + (extraCount > 0 ? 20 : 0),
          height: 24,
          child: Stack(
            children: [
              for (int i = 0; i < displayCount; i++)
                Positioned(
                  left: i * 14.0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getAvatarColor(i),
                      border: Border.all(
                        color: colors.surface,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        String.fromCharCode(65 + i), // A, B, C...
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              if (extraCount > 0)
                Positioned(
                  left: displayCount * 14.0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.textTertiary,
                      border: Border.all(
                        color: colors.surface,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '+$extraCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getAvatarColor(int index) {
    const colors = [
      FlowColors.primary,
      FlowColors.info,
      FlowColors.success,
    ];
    return colors[index % colors.length];
  }
}
