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
    // Start periodic cleanup timer (every 1 minute)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _runListCleanup();
    });
    // Run initial cleanup after a short delay
    Future.delayed(const Duration(seconds: 5), _runListCleanup);
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
      case 3: // Trash
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
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              // Drag handle
              GestureDetector(
                onTap: () {
                  // Toggle between half and full
                  final currentSize = _controller.size;
                  if (currentSize < 0.75) {
                    _controller.animateTo(
                      1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    _controller.animateTo(
                      0.5,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.flowColors.textTertiary.withAlpha(100),
                        borderRadius: BorderRadius.circular(2),
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

    // Find list name if a list is selected
    String title;
    if (selectedIndex >= 100 && selectedListId != null) {
      final list = lists.where((l) => l.id == selectedListId).firstOrNull;
      title = list?.name ?? 'List';
    } else {
      final titles = ['Today', 'Next 7 days', 'All', 'Trash'];
      title = selectedIndex < titles.length ? titles[selectedIndex] : 'Tasks';
    }

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
          // Admin panel
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: 'Admin',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AdminScreen(),
                ),
              );
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
    );
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
    final hasPending = syncState.pendingCount > 0;

    // Always show indicator (Saved, Saving, or unsaved count)

    // Success state - green checkmark that fades out
    if (_showSuccess) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_done_outlined,
                size: 16,
                color: colors.success,
              ),
              const SizedBox(width: 4),
              Text(
                'Synced',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.success,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Determine label text
    String label;
    if (isSyncing) {
      label = 'Saving...';
    } else if (isOffline) {
      label = 'Offline';
    } else if (hasPending) {
      label = syncState.pendingCount == 1
          ? '1 unsaved'
          : '${syncState.pendingCount} unsaved';
    } else {
      label = 'Saved';
    }

    // Normal sync state
    return Tooltip(
      message: isOffline
          ? 'Offline - ${syncState.pendingCount} changes pending'
          : hasPending
              ? '${syncState.pendingCount} changes to sync'
              : 'All changes saved',
      child: TextButton.icon(
        onPressed: isSyncing
            ? null
            : () => ref.read(syncEngineProvider).syncNow(),
        icon: isSyncing
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textTertiary,
                ),
              )
            : Icon(
                isOffline
                    ? Icons.cloud_off_outlined
                    : hasPending
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined,
                size: 16,
                color: isOffline
                    ? colors.warning
                    : hasPending
                        ? colors.textTertiary
                        : colors.success,
              ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isOffline
                ? colors.warning
                : hasPending
                    ? colors.textTertiary
                    : colors.success,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
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
    _SidebarItem(icon: Icons.delete_outline_rounded, label: 'Trash'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final lists = ref.watch(listTreeProvider);
    final archivedLists = ref.watch(archivedListTreeProvider);

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
