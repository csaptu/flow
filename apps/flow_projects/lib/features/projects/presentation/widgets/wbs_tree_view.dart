import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/providers/providers.dart';
import 'package:flow_projects/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

// Status color mapping for TaskStatus
Color _getTaskStatusColor(TaskStatus status) {
  switch (status) {
    case TaskStatus.pending:
      return FlowColors.statusNotStarted;
    case TaskStatus.inProgress:
      return FlowColors.statusInProgress;
    case TaskStatus.completed:
      return FlowColors.statusCompleted;
    case TaskStatus.cancelled:
    case TaskStatus.archived:
      return FlowColors.error;
  }
}

class WBSTreeView extends ConsumerWidget {
  const WBSTreeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wbsTreeAsync = ref.watch(wbsTreeProvider);
    final colors = context.flowColors;

    return wbsTreeAsync.when(
      data: (nodes) {
        if (nodes.isEmpty) {
          return _buildEmptyState(context);
        }

        return SingleChildScrollView(
          padding: FlowSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final node in nodes) _WBSNodeWidget(node: node, depth: 0),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(wbsTreeProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.flowColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No work breakdown structure yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add nodes to create your project structure',
            style: TextStyle(color: colors.textTertiary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              // TODO: Add root WBS node
            },
            icon: const Icon(Icons.add),
            label: const Text('Add First Node'),
          ),
        ],
      ),
    );
  }
}

class _WBSNodeWidget extends ConsumerWidget {
  final WBSTreeNode node;
  final int depth;

  const _WBSNodeWidget({
    required this.node,
    required this.depth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final expandedNodes = ref.watch(expandedWBSNodesProvider);
    final isExpanded = expandedNodes.contains(node.node.id);
    final statusColor = _getTaskStatusColor(node.node.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node row
        Container(
          margin: EdgeInsets.only(
            left: depth * FlowSpacing.wbsIndent,
            bottom: 4,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
            child: InkWell(
              onTap: () => _showNodeDetails(context, node.node),
              borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
              child: Padding(
                padding: FlowSpacing.wbsNodePadding,
                child: Row(
                  children: [
                    // Expand/collapse button
                    if (node.hasChildren)
                      InkWell(
                        onTap: () {
                          final current = ref.read(expandedWBSNodesProvider);
                          if (isExpanded) {
                            ref.read(expandedWBSNodesProvider.notifier).state =
                                current.difference({node.node.id});
                          } else {
                            ref.read(expandedWBSNodesProvider.notifier).state =
                                current.union({node.node.id});
                          }
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isExpanded
                                ? Icons.expand_more_rounded
                                : Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.textTertiary,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 26),

                    const SizedBox(width: 8),

                    // Status indicator
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Node name
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.node.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (node.node.description != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              node.node.description!,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Duration
                    if (node.node.plannedStart != null || node.node.plannedEnd != null) ...[
                      Icon(
                        Icons.schedule_outlined,
                        size: 14,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(node.node),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // Progress
                    SizedBox(
                      width: 60,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${node.node.progress}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Actions
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'add_child',
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 18),
                              SizedBox(width: 8),
                              Text('Add Child Node'),
                            ],
                          ),
                        ),
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
              ),
            ),
          ),
        ),

        // Children
        if (isExpanded && node.hasChildren)
          for (final child in node.children)
            _WBSNodeWidget(node: child, depth: depth + 1),
      ],
    );
  }

  String _formatDuration(WBSNode node) {
    final dateFormat = DateFormat('MMM d');
    if (node.plannedStart != null && node.plannedEnd != null) {
      return '${dateFormat.format(node.plannedStart!)} - ${dateFormat.format(node.plannedEnd!)}';
    }
    if (node.plannedStart != null) {
      return 'From ${dateFormat.format(node.plannedStart!)}';
    }
    if (node.plannedEnd != null) {
      return 'Due ${dateFormat.format(node.plannedEnd!)}';
    }
    return '';
  }

  void _showNodeDetails(BuildContext context, WBSNode node) {
    // TODO: Show node detail panel or dialog
  }
}
