import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/providers/providers.dart';
import 'package:flow_projects/core/theme/flow_theme.dart';
import 'package:flow_projects/features/projects/presentation/widgets/wbs_tree_view.dart';
import 'package:flow_projects/features/projects/presentation/widgets/gantt_chart.dart';
import 'package:intl/intl.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Set the selected project
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedProjectIdProvider.notifier).state = widget.projectId;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(selectedProjectProvider);
    final colors = context.flowColors;

    return Scaffold(
      body: projectAsync.when(
        data: (project) {
          if (project == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Project not found',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Header
              _ProjectHeader(project: project),

              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    bottom: BorderSide(color: colors.divider, width: 0.5),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: colors.primary,
                  unselectedLabelColor: colors.textSecondary,
                  indicatorColor: colors.primary,
                  indicatorWeight: 2,
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('WBS'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.view_timeline_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Gantt'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Team'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    const WBSTreeView(),
                    const GanttChart(),
                    _TeamView(project: project),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.invalidate(selectedProjectProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  final Project project;

  const _ProjectHeader({required this.project});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final statusColor = FlowColors.getStatusColor(project.status.name);
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      padding: const EdgeInsets.all(FlowSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
          ),
          const SizedBox(width: FlowSpacing.md),

          // Project info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 12),
                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatStatus(project.status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (project.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    project.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                // Metadata row
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateRange(project.startDate, project.targetDate, dateFormat),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(
                      Icons.people_outline,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${project.memberCount} members',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(
                      Icons.pie_chart_outline,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${project.progress.percentage.round()}% complete',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: Add WBS node
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Node'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  // TODO: Project settings
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatStatus(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.notStarted:
        return 'Not Started';
      case ProjectStatus.inProgress:
        return 'In Progress';
      case ProjectStatus.completed:
        return 'Completed';
      case ProjectStatus.onHold:
        return 'On Hold';
      case ProjectStatus.cancelled:
        return 'Cancelled';
    }
  }

  String _formatDateRange(DateTime? start, DateTime? end, DateFormat format) {
    if (start == null && end == null) {
      return 'No dates set';
    }
    if (start != null && end != null) {
      return '${format.format(start)} - ${format.format(end)}';
    }
    if (start != null) {
      return 'From ${format.format(start)}';
    }
    return 'Until ${format.format(end!)}';
  }
}

class _TeamView extends StatelessWidget {
  final Project project;

  const _TeamView({required this.project});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    if (project.memberCount <= 1) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No team members yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite team members to collaborate on this project',
              style: TextStyle(color: colors.textTertiary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                // TODO: Show invite dialog
              },
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Invite Members'),
            ),
          ],
        ),
      );
    }

    // TODO: Implement team member list
    return const Center(
      child: Text('Team members list coming soon'),
    );
  }
}
