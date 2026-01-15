import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/providers/providers.dart';
import 'package:flow_projects/core/theme/flow_theme.dart';
import 'package:flow_projects/features/projects/presentation/widgets/project_card.dart';
import 'package:flow_projects/features/projects/presentation/widgets/create_project_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Check auth on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final colors = context.flowColors;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _Sidebar(
            selectedIndex: selectedIndex,
            onItemTap: (index) {
              ref.read(selectedSidebarIndexProvider.notifier).state = index;
            },
          ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Header
                _Header(),

                // Content
                Expanded(
                  child: _buildContent(selectedIndex),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateProjectDialog(context),
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
    );
  }

  Widget _buildContent(int selectedIndex) {
    switch (selectedIndex) {
      case 0: // Active Projects
        return const _ProjectsGrid(showArchived: false);
      case 1: // Archived
        return const _ProjectsGrid(showArchived: true);
      case 2: // Templates
        return const _TemplatesView();
      default:
        return const _ProjectsGrid(showArchived: false);
    }
  }

  void _showCreateProjectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const CreateProjectDialog(),
    );
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final colors = context.flowColors;

    final titles = ['Active Projects', 'Archived', 'Templates'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            titles[selectedIndex],
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          // Search
          SizedBox(
            width: 240,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search projects...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Open settings
            },
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTap;

  const _Sidebar({
    required this.selectedIndex,
    required this.onItemTap,
  });

  static const _items = [
    _SidebarItem(icon: Icons.folder_open_rounded, label: 'Active'),
    _SidebarItem(icon: Icons.archive_outlined, label: 'Archived'),
    _SidebarItem(icon: Icons.dashboard_customize_outlined, label: 'Templates'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      width: FlowSpacing.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(
          right: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.all(FlowSpacing.lg),
            child: Row(
              children: [
                const Icon(
                  Icons.account_tree_rounded,
                  color: FlowColors.primary,
                  size: 28,
                ),
                const SizedBox(width: FlowSpacing.sm),
                Text(
                  'Flow Projects',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final isSelected = index == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: isSelected
                        ? colors.sidebarSelected
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                    child: InkWell(
                      onTap: () => onItemTap(index),
                      borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 20,
                              color: isSelected
                                  ? colors.primary
                                  : colors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // User section
          Consumer(
            builder: (context, ref, _) {
              final authState = ref.watch(authStateProvider);
              final user = authState.user;

              return Container(
                padding: const EdgeInsets.all(FlowSpacing.md),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.divider, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: colors.primary,
                      child: Text(
                        user?.name.substring(0, 1).toUpperCase() ?? 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'User',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.logout,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                      onPressed: () {
                        ref.read(authStateProvider.notifier).logout();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;

  const _SidebarItem({required this.icon, required this.label});
}

class _ProjectsGrid extends ConsumerWidget {
  final bool showArchived;

  const _ProjectsGrid({required this.showArchived});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = showArchived
        ? ref.watch(archivedProjectsProvider)
        : ref.watch(activeProjectsProvider);

    return projectsAsync.when(
      data: (projects) {
        if (projects.isEmpty) {
          return _buildEmptyState(context, showArchived);
        }

        return Padding(
          padding: FlowSpacing.screenPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth);

              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: FlowSpacing.md,
                  mainAxisSpacing: FlowSpacing.md,
                  childAspectRatio: 1.5,
                ),
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return ProjectCard(
                    project: project,
                    onTap: () => context.go('/project/${project.id}'),
                  );
                },
              );
            },
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
              onPressed: () {
                if (showArchived) {
                  ref.invalidate(archivedProjectsProvider);
                } else {
                  ref.invalidate(activeProjectsProvider);
                }
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  int _calculateCrossAxisCount(double width) {
    if (width >= 1200) return 4;
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }

  Widget _buildEmptyState(BuildContext context, bool isArchived) {
    final colors = context.flowColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isArchived ? Icons.archive_outlined : Icons.folder_open_outlined,
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            isArchived
                ? 'No archived projects'
                : 'No projects yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            isArchived
                ? 'Completed projects will appear here'
                : 'Create your first project to get started',
            style: TextStyle(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _TemplatesView extends StatelessWidget {
  const _TemplatesView();

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Project Templates',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Templates feature coming soon',
            style: TextStyle(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
