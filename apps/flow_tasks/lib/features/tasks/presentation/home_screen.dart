import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart' show Task, TaskList;
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/sync/sync_types.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_list.dart' as widgets;
import 'package:flow_tasks/features/tasks/presentation/widgets/expandable_task_tile.dart' as widgets;
import 'package:flow_tasks/features/tasks/presentation/widgets/quick_add_bar.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_detail_panel.dart';
import 'package:flow_tasks/features/settings/presentation/settings_screen.dart';
import 'package:flow_tasks/features/admin/presentation/admin_screen.dart';

/// Breakpoint for showing side panel vs bottom sheet
const _wideScreenBreakpoint = 900.0;
const _detailPanelWidth = 380.0;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _sidebarWidth = FlowSpacing.sidebarWidth;
  static const _minSidebarWidth = 180.0;
  static const _maxSidebarWidth = 400.0;

  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();
    // Start periodic cleanup timer (every 10 minutes - less aggressive)
    // Cleanup only removes lists whose hashtags are no longer in any tasks
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _runListCleanup();
    });
    // Don't run cleanup on startup - wait for lists to sync properly first
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  void _runListCleanup() {
    if (mounted) {
      ref.read(listCleanupProvider.notifier).runCleanup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final selectedTask = ref.watch(selectedTaskProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= _wideScreenBreakpoint;

    // Show bottom sheet on narrow screens when task is selected
    if (!isWideScreen && selectedTask != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTaskBottomSheet(context, selectedTask);
      });
    }

    return Scaffold(
      body: Row(
        children: [
          // Sidebar (hide on very narrow screens)
          if (screenWidth >= 600)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Sidebar(
                  selectedIndex: selectedIndex,
                  width: _sidebarWidth,
                  onItemTap: (index) {
                    ref.read(selectedSidebarIndexProvider.notifier).state = index;
                    ref.read(selectedListIdProvider.notifier).state = null; // Clear list selection
                  },
                ),
                // Resize handle
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _sidebarWidth = (_sidebarWidth + details.delta.dx)
                            .clamp(_minSidebarWidth, _maxSidebarWidth);
                      });
                    },
                    child: Container(
                      width: 4,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 1,
                          color: context.flowColors.divider.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Header
                _Header(),

                // Task list
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: FlowSpacing.taskListMaxWidth,
                      ),
                      child: Column(
                        children: [
                          // Quick add bar
                          const QuickAddBar(),

                          // Tasks
                          Expanded(
                            child: _buildTaskList(selectedIndex),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Detail panel (wide screen only)
          if (isWideScreen && selectedTask != null)
            SizedBox(
              width: _detailPanelWidth,
              child: TaskDetailPanel(
                task: selectedTask,
                onClose: () {
                  ref.read(selectedTaskIdProvider.notifier).state = null;
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showTaskBottomSheet(BuildContext context, Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => _DraggableTaskSheet(task: task),
    ).whenComplete(() {
      // Clear selection when sheet is dismissed
      if (mounted) {
        ref.read(selectedTaskIdProvider.notifier).state = null;
      }
    });

    // Clear selection so we don't show the sheet again
    ref.read(selectedTaskIdProvider.notifier).state = null;
  }

  Widget _buildTaskList(int selectedIndex) {
    switch (selectedIndex) {
      case 0: // Today
        return const widgets.TaskList(type: widgets.TaskListType.today);
      case 1: // Next 7 days
        return const widgets.TaskList(type: widgets.TaskListType.next7days);
      case 2: // All
        return const widgets.TaskList(type: widgets.TaskListType.all);
      case 3: // Completed
        return const widgets.TaskList(type: widgets.TaskListType.completed);
      case 4: // Trash
        return const widgets.TaskList(type: widgets.TaskListType.trash);
      default:
        // Index >= 100 means a list is selected
        if (selectedIndex >= 100) {
          return const _ListTaskList();
        }
        return const widgets.TaskList(type: widgets.TaskListType.next7days);
    }
  }
}

/// Task list widget for viewing a specific list's tasks
class _ListTaskList extends ConsumerWidget {
  const _ListTaskList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listTasks = ref.watch(selectedListTasksProvider);

    return listTasks.when(
      data: (tasks) {
        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tag, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No tasks in this list.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return widgets.ExpandableTaskTile(
              task: task,
              onComplete: () => _completeTask(ref, task),
              onUncomplete: () => _uncompleteTask(ref, task),
              onDelete: () => _deleteTask(ref, task),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Error loading tasks')),
    );
  }

  Future<void> _completeTask(WidgetRef ref, Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.complete(task.id);
  }

  Future<void> _uncompleteTask(WidgetRef ref, Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.uncomplete(task.id);
  }

  Future<void> _deleteTask(WidgetRef ref, Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.delete(task.id);
  }
}

/// Draggable bottom sheet for task detail on mobile
class _DraggableTaskSheet extends ConsumerStatefulWidget {
  final Task task;

  const _DraggableTaskSheet({required this.task});

  @override
  ConsumerState<_DraggableTaskSheet> createState() => _DraggableTaskSheetState();
}

class _DraggableTaskSheetState extends ConsumerState<_DraggableTaskSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSizeChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSizeChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSizeChanged() {
    // When dragged up past 0.9, snap to full screen
    if (_controller.size > 0.9 && _controller.size < 1.0) {
      _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleTap() {
    // If at full screen, go back to half. Otherwise close.
    if (_controller.size > 0.9) {
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.5, 1.0],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.flowColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle - tap to close/collapse
              GestureDetector(
                onTap: _handleTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 3,
                      decoration: BoxDecoration(
                        color: context.flowColors.textTertiary.withAlpha(80),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: TaskDetailPanel(
                  task: widget.task,
                  isBottomSheet: true,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final colors = context.flowColors;
    final selectedListId = ref.watch(selectedListIdProvider);
    final lists = ref.watch(listsProvider);
    final groupByDate = ref.watch(groupByDateProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;

    // Find list name if a list is selected
    String title;
    if (selectedIndex >= 100 && selectedListId != null) {
      final list = lists.where((l) => l.id == selectedListId).firstOrNull;
      title = list?.name ?? 'List';
    } else {
      final titles = ['Today', 'Next 7 days', 'All', 'Completed', 'Trash'];
      title = selectedIndex < titles.length ? titles[selectedIndex] : 'Tasks';
    }

    // Show group by date button for views that support it (not trash)
    final showGroupByDate = selectedIndex != 4; // 4 = Trash

    // Mobile layout: two rows (hamburger + actions, then title)
    if (isNarrowScreen) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.divider, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // First row: hamburger menu + action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  // Hamburger menu button
                  IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'Lists',
                    onPressed: () => _showListsDrawer(context, ref),
                  ),
                  const Spacer(),
                  // Sync indicator
                  const _SyncIndicator(),
                  // Group by Date toggle
                  if (showGroupByDate)
                    IconButton(
                      icon: Icon(
                        Icons.view_agenda_outlined,
                        color: groupByDate ? colors.primary : colors.textSecondary,
                      ),
                      tooltip: groupByDate ? 'Ungroup tasks' : 'Group by date',
                      onPressed: () {
                        ref.read(groupByDateProvider.notifier).state = !groupByDate;
                      },
                    ),
                  // Settings
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Second row: List name
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Desktop layout: single row
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
            title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          // Sync indicator with success animation
          const _SyncIndicator(),
          // Group by Date toggle
          if (showGroupByDate)
            Tooltip(
              message: groupByDate ? 'Ungroup tasks' : 'Group by date',
              child: IconButton(
                icon: Icon(
                  Icons.view_agenda_outlined,
                  color: groupByDate ? colors.primary : colors.textSecondary,
                ),
                onPressed: () {
                  ref.read(groupByDateProvider.notifier).state = !groupByDate;
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showListsDrawer(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ListsDrawer(),
    );
  }
}

/// Bottom sheet drawer for selecting lists on mobile
class _ListsDrawer extends ConsumerWidget {
  const _ListsDrawer();

  static const _items = [
    (icon: Icons.today_rounded, label: 'Today', index: 0),
    (icon: Icons.date_range_rounded, label: 'Next 7 days', index: 1),
    (icon: Icons.all_inbox_rounded, label: 'All', index: 2),
    (icon: Icons.check_circle_outline_rounded, label: 'Completed', index: 3),
    (icon: Icons.delete_outline_rounded, label: 'Trash', index: 4),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final selectedListId = ref.watch(selectedListIdProvider);
    final lists = ref.watch(listTreeProvider);
    final archivedLists = ref.watch(archivedListTreeProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withAlpha(100),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: FlowColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Flow',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Main navigation items
                    ..._items.map((item) {
                      final isSelected = item.index == selectedIndex && selectedListId == null;
                      return _DrawerItem(
                        icon: item.icon,
                        label: item.label,
                        isSelected: isSelected,
                        onTap: () {
                          ref.read(selectedSidebarIndexProvider.notifier).state = item.index;
                          ref.read(selectedListIdProvider.notifier).state = null;
                          Navigator.of(context).pop();
                        },
                      );
                    }),

                    // Lists section
                    if (lists.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(
                          'Lists',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      ...lists.map((list) => _DrawerListItem(
                        list: list,
                        isSelected: selectedListId == list.id,
                        isArchived: false,
                        onTap: () {
                          ref.read(selectedListIdProvider.notifier).state = list.id;
                          ref.read(selectedSidebarIndexProvider.notifier).state = 100;
                          Navigator.of(context).pop();
                        },
                      )),
                    ],

                    // Archived lists section
                    if (archivedLists.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.archive_outlined,
                              size: 14,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Archived',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...archivedLists.map((list) => _DrawerListItem(
                        list: list,
                        isSelected: selectedListId == list.id,
                        isArchived: true,
                        onTap: () {
                          ref.read(selectedListIdProvider.notifier).state = list.id;
                          ref.read(selectedSidebarIndexProvider.notifier).state = 100;
                          Navigator.of(context).pop();
                        },
                      )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Drawer navigation item
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected ? colors.sidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? colors.textPrimary : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawer list item
class _DrawerListItem extends StatelessWidget {
  final TaskList list;
  final bool isSelected;
  final bool isArchived;
  final VoidCallback onTap;

  const _DrawerListItem({
    required this.list,
    required this.isSelected,
    required this.isArchived,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            color: isSelected ? colors.sidebarSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.tag,
                      size: 18,
                      color: isSelected
                          ? colors.primary
                          : isArchived
                              ? colors.textTertiary
                              : (list.color != null
                                  ? _parseColor(list.color!)
                                  : colors.textSecondary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        list.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? colors.textPrimary
                              : isArchived
                                  ? colors.textTertiary
                                  : colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (list.taskCount > 0)
                      Text(
                        '${list.taskCount}',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Sublists
        if (list.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: list.children.map((sublist) => _DrawerListItem(
                list: sublist,
                isSelected: false, // TODO: check properly
                isArchived: isArchived,
                onTap: onTap,
              )).toList(),
            ),
          ),
      ],
    );
  }

  Color _parseColor(String color) {
    if (color.startsWith('#')) {
      return Color(int.parse(color.substring(1), radix: 16) + 0xFF000000);
    }
    return Colors.grey;
  }
}

class _SyncIndicator extends ConsumerStatefulWidget {
  const _SyncIndicator();

  @override
  ConsumerState<_SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends ConsumerState<_SyncIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _showSuccess = false;
  int _lastPendingCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showSuccess = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStateProvider);
    final colors = context.flowColors;

    // Detect sync completion: had pending, now synced with 0 pending
    if (_lastPendingCount > 0 &&
        syncState.pendingCount == 0 &&
        syncState.status == SyncStatus.synced) {
      // Show success state
      _showSuccess = true;
      _controller.reset();
      // Start fade out after delay
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _controller.forward();
      });
    }
    _lastPendingCount = syncState.pendingCount;

    final isSyncing = syncState.status == SyncStatus.syncing;
    final isOffline = syncState.status == SyncStatus.offline;

    // Success state - brief "Saved" that fades out
    if (_showSuccess) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'Saved',
            style: TextStyle(
              fontSize: 12,
              color: colors.textTertiary,
            ),
          ),
        ),
      );
    }

    // Only show indicator when syncing or offline
    // Don't show "N unsaved" - optimistic updates handle this silently
    if (isSyncing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Saving',
              style: TextStyle(
                fontSize: 12,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    if (isOffline) {
      return Tooltip(
        message: 'Offline - changes will sync when connected',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 14,
                color: colors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                'Offline',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.warning,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Hide when everything is normal (synced or pending)
    return const SizedBox.shrink();
  }
}

class _Sidebar extends ConsumerWidget {
  final int selectedIndex;
  final double width;
  final Function(int) onItemTap;

  const _Sidebar({
    required this.selectedIndex,
    required this.width,
    required this.onItemTap,
  });

  static const _items = [
    _SidebarItem(icon: Icons.today_rounded, label: 'Today'),
    _SidebarItem(icon: Icons.date_range_rounded, label: 'Next 7 days'),
    _SidebarItem(icon: Icons.all_inbox_rounded, label: 'All'),
    _SidebarItem(icon: Icons.check_circle_outline_rounded, label: 'Completed'),
    _SidebarItem(icon: Icons.delete_outline_rounded, label: 'Trash'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final lists = ref.watch(listTreeProvider);
    final archivedLists = ref.watch(archivedListTreeProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Container(
      width: width,
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
                  Icons.check_circle,
                  color: FlowColors.primary,
                  size: 28,
                ),
                const SizedBox(width: FlowSpacing.sm),
                Text(
                  'Flow',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),

          // Navigation items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // Main navigation items
                ..._items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
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
                }),

                // Lists section
                if (lists.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Lists',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            // TODO: Show create list dialog
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...lists.map((list) => _ListItem(
                    list: list,
                    isArchived: false,
                    isSelected: ref.watch(selectedListIdProvider) == list.id,
                    onTap: () {
                      ref.read(selectedListIdProvider.notifier).state = list.id;
                      ref.read(selectedSidebarIndexProvider.notifier).state = 100; // List mode
                    },
                  )),
                ],

                // Archived lists section
                if (archivedLists.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.archive_outlined,
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Archived',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...archivedLists.map((list) => _ListItem(
                    list: list,
                    isArchived: true,
                    isSelected: ref.watch(selectedListIdProvider) == list.id,
                    onTap: () {
                      ref.read(selectedListIdProvider.notifier).state = list.id;
                      ref.read(selectedSidebarIndexProvider.notifier).state = 100; // List mode
                    },
                  )),
                ],
              ],
            ),
          ),

          // Bottom actions: Settings and Admin
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Settings button (subtle)
                Tooltip(
                  message: 'Settings',
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.tune,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
                // Admin button (only show if admin)
                isAdmin.when(
                  data: (admin) => admin
                      ? Tooltip(
                          message: 'Admin',
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AdminScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.shield_outlined,
                                size: 18,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListItem extends ConsumerStatefulWidget {
  final TaskList list;
  final bool isSelected;
  final bool isArchived;
  final VoidCallback onTap;

  const _ListItem({
    required this.list,
    required this.isSelected,
    required this.isArchived,
    required this.onTap,
  });

  @override
  ConsumerState<_ListItem> createState() => _ListItemState();
}

class _ListItemState extends ConsumerState<_ListItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final selectedListId = ref.watch(selectedListIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            child: Material(
              color: widget.isSelected ? colors.sidebarSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tag,
                        size: 16,
                        color: widget.isSelected
                            ? colors.primary
                            : widget.isArchived
                                ? colors.textTertiary
                                : (widget.list.color != null
                                    ? _parseColor(widget.list.color!)
                                    : colors.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.list.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.normal,
                            color: widget.isSelected
                                ? colors.textPrimary
                                : widget.isArchived
                                    ? colors.textTertiary
                                    : colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Task count (when not hovering)
                      if (!_isHovering && widget.list.taskCount > 0)
                        Text(
                          '${widget.list.taskCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textTertiary,
                          ),
                        ),
                      // Archive/Recover button (when hovering)
                      if (_isHovering)
                        Tooltip(
                          message: widget.isArchived ? 'Restore' : 'Archive',
                          child: InkWell(
                            onTap: () => _handleArchiveAction(),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                widget.isArchived
                                    ? Icons.unarchive_outlined
                                    : Icons.archive_outlined,
                                size: 16,
                                color: colors.textTertiary,
                              ),
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
        // Sublists
        if (widget.list.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: widget.list.children.map((sublist) => _ListItem(
                list: sublist,
                isArchived: widget.isArchived,
                isSelected: selectedListId == sublist.id,
                onTap: () {
                  ref.read(selectedListIdProvider.notifier).state = sublist.id;
                  ref.read(selectedSidebarIndexProvider.notifier).state = 100; // List mode
                },
              )).toList(),
            ),
          ),
      ],
    );
  }

  void _handleArchiveAction() async {
    final listActions = ref.read(listActionsProvider);
    if (widget.isArchived) {
      await listActions.unarchive(widget.list.id);
    } else {
      await listActions.archive(widget.list.id);
      // Clear selection if we archived the selected list
      if (ref.read(selectedListIdProvider) == widget.list.id) {
        ref.read(selectedListIdProvider.notifier).state = null;
        ref.read(selectedSidebarIndexProvider.notifier).state = 1; // Back to Next 7 days
      }
    }
  }

  Color _parseColor(String color) {
    if (color.startsWith('#')) {
      return Color(int.parse(color.substring(1), radix: 16) + 0xFF000000);
    }
    return Colors.grey;
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;

  const _SidebarItem({required this.icon, required this.label});
}
