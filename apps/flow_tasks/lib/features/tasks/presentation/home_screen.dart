import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart' show Task, TaskList, TaskStatus, AdminUser, Order, AIPromptConfig;
import 'package:intl/intl.dart';
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

/// Breakpoint for showing side panel vs bottom sheet
const _wideScreenBreakpoint = 700.0;
const _detailPanelWidth = 320.0;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _sidebarWidth = FlowSpacing.sidebarWidth;
  static const _minSidebarWidth = 180.0;
  static const _maxSidebarWidth = 400.0;
  bool _isShowingSheet = false;
  String? _sheetTaskId; // Track which task is shown in bottom sheet

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final selectedTask = ref.watch(selectedTaskProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= _wideScreenBreakpoint;

    // When resizing from narrow to wide while bottom sheet is open,
    // close the sheet and restore task selection for side panel
    if (isWideScreen && _isShowingSheet && _sheetTaskId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isShowingSheet && mounted) {
          final taskId = _sheetTaskId;
          Navigator.of(context).pop(); // Close bottom sheet
          // Restore selection so side panel shows
          ref.read(selectedTaskIdProvider.notifier).state = taskId;
        }
      });
    }

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
          if (screenWidth >= 450)
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
                          // Quick add bar (hide for admin views: 10, 11, 12)
                          if (selectedIndex < 10 || selectedIndex >= 100)
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
    if (_isShowingSheet) {
      debugPrint('[TaskSheet] Already showing a sheet, ignoring');
      return;
    }
    _isShowingSheet = true;
    _sheetTaskId = task.id; // Track which task is in the sheet
    debugPrint('[TaskSheet] Showing bottom sheet for task: ${task.id}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      enableDrag: false, // We handle drag via DraggableScrollableSheet
      builder: (context) => _DraggableTaskSheet(task: task),
    ).whenComplete(() {
      debugPrint('[TaskSheet] Bottom sheet completed/dismissed');
      _isShowingSheet = false;
      _sheetTaskId = null;
      // Clear selection when sheet is dismissed (unless transitioning to wide screen)
      if (mounted) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isWideScreen = screenWidth >= _wideScreenBreakpoint;
        if (!isWideScreen) {
          ref.read(selectedTaskIdProvider.notifier).state = null;
        }
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
      case 10: // Admin: Users
        return const _AdminUsersView();
      case 11: // Admin: Orders
        return const _AdminOrdersView();
      case 12: // Admin: AI Services
        return const _AdminAIServicesView();
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
    final tasks = ref.watch(selectedListTasksProvider);

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
  double _dragStartSize = 0.5;
  double _totalDragDelta = 0; // Track total drag direction
  bool _isClosing = false;

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
    // No auto-snap during drag - we handle it in _onDragEnd
  }

  void _close() {
    debugPrint('[TaskSheet] _close called - isClosing: $_isClosing, mounted: $mounted');
    if (_isClosing) {
      debugPrint('[TaskSheet] Already closing, ignoring');
      return;
    }
    if (!mounted) {
      debugPrint('[TaskSheet] Not mounted, ignoring');
      return;
    }
    _isClosing = true;

    // Check if we can actually pop
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      debugPrint('[TaskSheet] Popping bottom sheet');
      navigator.pop();
    } else {
      debugPrint('[TaskSheet] ERROR: Cannot pop! This would cause blank page');
      _isClosing = false; // Reset so user can try again
    }
  }

  void _handleTap() {
    if (_isClosing) return;
    // If at full screen, go back to half. Otherwise close.
    if (_controller.size > 0.75) {
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _close();
    }
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartSize = _controller.size;
    _totalDragDelta = 0;
    debugPrint('[TaskSheet] Drag start at size: $_dragStartSize');
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isClosing) return;
    final screenHeight = MediaQuery.of(context).size.height;
    // Negative dy = dragging up = increase size
    final delta = -details.delta.dy / screenHeight;
    _totalDragDelta += delta; // Positive = dragged up, Negative = dragged down
    final newSize = (_controller.size + delta).clamp(0.3, 1.0);
    _controller.jumpTo(newSize);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isClosing) return;

    final draggedUp = _totalDragDelta > 0.01; // Small threshold to ignore tiny movements
    final draggedDown = _totalDragDelta < -0.01;

    debugPrint('[TaskSheet] Drag end - startSize: $_dragStartSize, totalDelta: $_totalDragDelta, up: $draggedUp, down: $draggedDown');

    // Simple two-step logic:
    // From half (<=0.75): up → full, down → close
    // From full (>0.75): down → half, up → stay full

    if (_dragStartSize > 0.75) {
      // Started from full position
      if (draggedDown) {
        // Drag down from full → go to half
        debugPrint('[TaskSheet] Full → Half');
        _controller.animateTo(0.5, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        // Stay at full (or dragged up more)
        debugPrint('[TaskSheet] Stay Full');
        _controller.animateTo(1.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } else {
      // Started from half position
      if (draggedUp) {
        // Drag up from half → go to full
        debugPrint('[TaskSheet] Half → Full');
        _controller.animateTo(1.0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else if (draggedDown) {
        // Drag down from half → close
        debugPrint('[TaskSheet] Half → Close');
        _close();
      } else {
        // No significant drag, stay at half
        debugPrint('[TaskSheet] Stay Half');
        _controller.animateTo(0.5, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
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
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              // Drag handle - dragging here resizes the sheet (works on both touch and mouse)
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: _handleTap,
                  onVerticalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  behavior: HitTestBehavior.opaque,
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
              ),
              // Content - fills remaining space
              SliverFillRemaining(
                hasScrollBody: false,
                child: TaskDetailPanel(
                  task: widget.task,
                  isBottomSheet: true,
                  onClose: _close,
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
    final isNarrowScreen = screenWidth < 450;

    // Find list name if a list is selected
    String title;
    if (selectedIndex >= 100 && selectedListId != null) {
      final list = lists.where((l) => l.id == selectedListId).firstOrNull;
      title = list?.name ?? 'List';
    } else if (selectedIndex == 10) {
      title = 'Users';
    } else if (selectedIndex == 11) {
      title = 'Orders';
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
                  // Global search
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search tasks',
                    onPressed: () => _showGlobalSearch(context, ref),
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
          // Global search
          Tooltip(
            message: 'Search tasks',
            child: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _showGlobalSearch(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  void _showGlobalSearch(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const _GlobalSearchDialog(),
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

                    // Lists section (collapsible)
                    if (lists.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _CollapsibleDrawerListsSection(
                        lists: lists,
                        selectedListId: selectedListId,
                        onListTap: (listId) {
                          ref.read(selectedListIdProvider.notifier).state = listId;
                          ref.read(selectedSidebarIndexProvider.notifier).state = 100;
                          Navigator.of(context).pop();
                        },
                      ),
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
  final VoidCallback onTap;

  const _DrawerListItem({
    required this.list,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    // Add left indent for nested lists (16px per depth level)
    final leftIndent = list.depth * 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 12 + leftIndent, right: 12, top: 2, bottom: 2),
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
                      size: list.depth > 0 ? 14 : 18, // Smaller icon for sublists
                      color: isSelected
                          ? colors.primary
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
                          color: isSelected ? colors.textPrimary : colors.textSecondary,
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

/// Collapsible Lists section for mobile drawer
class _CollapsibleDrawerListsSection extends ConsumerStatefulWidget {
  final List<TaskList> lists;
  final String? selectedListId;
  final void Function(String) onListTap;

  const _CollapsibleDrawerListsSection({
    required this.lists,
    required this.selectedListId,
    required this.onListTap,
  });

  @override
  ConsumerState<_CollapsibleDrawerListsSection> createState() => _CollapsibleDrawerListsSectionState();
}

class _CollapsibleDrawerListsSectionState extends ConsumerState<_CollapsibleDrawerListsSection> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isExpanded = ref.watch(listsExpandedProvider);
    final searchQuery = ref.watch(listSearchQueryProvider);
    final filteredLists = ref.watch(filteredListsProvider);

    final displayLists = searchQuery.isEmpty ? widget.lists : filteredLists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              // Expand/collapse button + label
              InkWell(
                onTap: () {
                  ref.read(listsExpandedProvider.notifier).state = !isExpanded;
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 18,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Lists',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${widget.lists.length})',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Search toggle
              if (isExpanded)
                InkWell(
                  onTap: () {
                    setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchController.clear();
                        ref.read(listSearchQueryProvider.notifier).state = '';
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _showSearch ? Icons.close : Icons.search,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Search field
        if (isExpanded && _showSearch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search lists...',
                  hintStyle: TextStyle(fontSize: 14, color: colors.textTertiary),
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
                onChanged: (value) {
                  ref.read(listSearchQueryProvider.notifier).state = value;
                },
              ),
            ),
          ),

        // List items
        if (isExpanded)
          ...displayLists.map((list) => _DrawerListItem(
            list: list,
            isSelected: widget.selectedListId == list.id,
            onTap: () => widget.onListTap(list.id),
          )),

        // No results message
        if (isExpanded && _showSearch && searchQuery.isNotEmpty && displayLists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'No lists found',
              style: TextStyle(fontSize: 13, color: colors.textTertiary),
            ),
          ),
      ],
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

class _Sidebar extends ConsumerStatefulWidget {
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
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  bool _adminExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final lists = ref.watch(listTreeProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Container(
      width: widget.width,
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
                ..._Sidebar._items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final isSelected = index == widget.selectedIndex;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: isSelected
                          ? colors.sidebarSelected
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                      child: InkWell(
                        onTap: () => widget.onItemTap(index),
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

                // Lists section (collapsible)
                if (lists.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _CollapsibleListsSection(
                    lists: lists,
                    selectedListId: ref.watch(selectedListIdProvider),
                    onListTap: (listId) {
                      ref.read(selectedListIdProvider.notifier).state = listId;
                      ref.read(selectedSidebarIndexProvider.notifier).state = 100;
                    },
                  ),
                ],
              ],
            ),
          ),

          // Bottom actions: Admin toggle + Settings
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.divider, width: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Admin items (expanded)
                if (_adminExpanded)
                  isAdmin.when(
                    data: (admin) => admin
                        ? Column(
                            children: [
                              // Users
                              _AdminBottomItem(
                                icon: Icons.people_outline,
                                label: 'Users',
                                isSelected: widget.selectedIndex == 10,
                                onTap: () => widget.onItemTap(10),
                              ),
                              // Orders
                              _AdminBottomItem(
                                icon: Icons.receipt_long_outlined,
                                label: 'Orders',
                                isSelected: widget.selectedIndex == 11,
                                onTap: () => widget.onItemTap(11),
                              ),
                              // AI Services
                              _AdminBottomItem(
                                icon: Icons.psychology_outlined,
                                label: 'AI Services',
                                isSelected: widget.selectedIndex == 12,
                                onTap: () => widget.onItemTap(12),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                // Settings and Admin toggle row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      // Admin toggle (only for admins)
                      isAdmin.when(
                        data: (admin) => admin
                            ? Tooltip(
                                message: _adminExpanded ? 'Hide admin' : 'Show admin',
                                child: InkWell(
                                  onTap: () => setState(() => _adminExpanded = !_adminExpanded),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.admin_panel_settings_outlined,
                                      size: 18,
                                      color: _adminExpanded ? colors.primary : colors.textTertiary,
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
          ),
        ],
      ),
    );
  }
}

/// Admin item shown in the bottom section when admin toggle is expanded
class _AdminBottomItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdminBottomItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: isSelected ? colors.sidebarSelected : Colors.transparent,
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListItem extends ConsumerWidget {
  final TaskList list;
  final bool isSelected;
  final VoidCallback onTap;

  const _ListItem({
    required this.list,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.flowColors;
    final selectedListId = ref.watch(selectedListIdProvider);

    // Add left indent for nested lists (12px per depth level)
    final leftIndent = list.depth * 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: leftIndent, bottom: 2),
          child: Material(
            color: isSelected ? colors.sidebarSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
            child: InkWell(
              onTap: onTap,
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
                      size: list.depth > 0 ? 14 : 16, // Smaller icon for sublists
                      color: isSelected
                          ? colors.primary
                          : (list.color != null
                              ? _parseColor(list.color!)
                              : colors.textSecondary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        list.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                          color: isSelected ? colors.textPrimary : colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Task count
                    if (list.taskCount > 0)
                      Text(
                        '${list.taskCount}',
                        style: TextStyle(
                          fontSize: 12,
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
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: list.children.map((sublist) => _ListItem(
                list: sublist,
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

/// Collapsible Lists section with search
class _CollapsibleListsSection extends ConsumerStatefulWidget {
  final List<TaskList> lists;
  final String? selectedListId;
  final void Function(String) onListTap;

  const _CollapsibleListsSection({
    required this.lists,
    required this.selectedListId,
    required this.onListTap,
  });

  @override
  ConsumerState<_CollapsibleListsSection> createState() => _CollapsibleListsSectionState();
}

class _CollapsibleListsSectionState extends ConsumerState<_CollapsibleListsSection> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isExpanded = ref.watch(listsExpandedProvider);
    final searchQuery = ref.watch(listSearchQueryProvider);
    final filteredLists = ref.watch(filteredListsProvider);

    // Use filtered lists when searching, otherwise use all lists
    final displayLists = searchQuery.isEmpty ? widget.lists : filteredLists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: Lists label + expand/collapse + search toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              // Expand/collapse button + label
              InkWell(
                onTap: () {
                  ref.read(listsExpandedProvider.notifier).state = !isExpanded;
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Lists',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${widget.lists.length})',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Search toggle button
              if (isExpanded)
                InkWell(
                  onTap: () {
                    setState(() {
                      _showSearch = !_showSearch;
                      if (!_showSearch) {
                        _searchController.clear();
                        ref.read(listSearchQueryProvider.notifier).state = '';
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _showSearch ? Icons.close : Icons.search,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Search field (when expanded and search is active)
        if (isExpanded && _showSearch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search lists...',
                  hintStyle: TextStyle(fontSize: 13, color: colors.textTertiary),
                  prefixIcon: Icon(Icons.search, size: 16, color: colors.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
                onChanged: (value) {
                  ref.read(listSearchQueryProvider.notifier).state = value;
                },
              ),
            ),
          ),

        // List items (when expanded)
        if (isExpanded)
          ...displayLists.map((list) => _ListItem(
            list: list,
            isSelected: widget.selectedListId == list.id,
            onTap: () => widget.onListTap(list.id),
          )),

        // "No results" message
        if (isExpanded && _showSearch && searchQuery.isNotEmpty && displayLists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No lists found',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// Global search dialog for searching all tasks
class _GlobalSearchDialog extends ConsumerStatefulWidget {
  const _GlobalSearchDialog();

  @override
  ConsumerState<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    // Clear search when dialog closes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(globalSearchQueryProvider.notifier).state = '';
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final results = ref.watch(globalSearchResultsProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.9 : 500.0;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search input
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Search tasks...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            ref.read(globalSearchQueryProvider.notifier).state = '';
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  ref.read(globalSearchQueryProvider.notifier).state = value;
                  setState(() {});
                },
              ),
            ),
            // Results
            if (_controller.text.isNotEmpty) ...[
              Divider(height: 1, color: colors.divider),
              Flexible(
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, size: 48, color: colors.textTertiary),
                            const SizedBox(height: 12),
                            Text(
                              'No tasks found',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final task = results[index];
                          return _SearchResultItem(
                            task: task,
                            onTap: () {
                              Navigator.of(context).pop();
                              // Select the task
                              ref.read(selectedTaskIdProvider.notifier).state = task.id;
                              // Switch to All view to ensure task is visible
                              ref.read(selectedSidebarIndexProvider.notifier).state = 2;
                              ref.read(selectedListIdProvider.notifier).state = null;
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Search result item
class _SearchResultItem extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;

  const _SearchResultItem({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isCompleted = task.status == TaskStatus.completed;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? colors.success
                    : (task.isOverdue ? colors.error : colors.primary),
              ),
            ),
            const SizedBox(width: 12),
            // Task info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.aiSummary ?? task.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isCompleted ? colors.textTertiary : colors.textPrimary,
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (task.description != null && task.description!.isNotEmpty)
                    Text(
                      task.description!.replaceAll('\n', ' '),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Status badge
            if (isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.success.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Done',
                  style: TextStyle(fontSize: 10, color: colors.success),
                ),
              )
            else if (task.isOverdue)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.error.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Overdue',
                  style: TextStyle(fontSize: 10, color: colors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Admin Users View - integrated into main content area
class _AdminUsersView extends ConsumerStatefulWidget {
  const _AdminUsersView();

  @override
  ConsumerState<_AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends ConsumerState<_AdminUsersView> {
  String _tierFilter = 'all';
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final usersAsync = ref.watch(adminUsersProvider((
      tier: _tierFilter == 'all' ? null : _tierFilter,
      page: _page,
    )));

    return Column(
      children: [
        // Filter bar
        _AdminFilterBar(
          selectedTier: _tierFilter,
          onTierChanged: (tier) => setState(() {
            _tierFilter = tier;
            _page = 1;
          }),
        ),
        // Content
        Expanded(
          child: usersAsync.when(
            data: (response) {
              if (response.items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: colors.textTertiary),
                      const SizedBox(height: 16),
                      Text('No users found', style: TextStyle(color: colors.textSecondary)),
                    ],
                  ),
                );
              }
              final totalPages = response.meta?.totalPages ?? 1;
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: response.items.length,
                      itemBuilder: (context, index) {
                        final user = response.items[index];
                        return _AdminUserTile(
                          user: user,
                          onTap: () => _showEditUserDialog(user),
                        );
                      },
                    ),
                  ),
                  if (totalPages > 1)
                    _AdminPagination(
                      page: _page,
                      totalPages: totalPages,
                      onPageChanged: (page) => setState(() => _page = page),
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 16),
                  Text('Failed to load users', style: TextStyle(color: colors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(err.toString(), style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.invalidate(adminUsersProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditUserDialog(AdminUser user) {
    showDialog(
      context: context,
      builder: (context) => _AdminEditUserDialog(user: user),
    ).then((updated) {
      if (updated == true) {
        ref.invalidate(adminUsersProvider);
      }
    });
  }
}

/// Admin Orders View - integrated into main content area
class _AdminOrdersView extends ConsumerStatefulWidget {
  const _AdminOrdersView();

  @override
  ConsumerState<_AdminOrdersView> createState() => _AdminOrdersViewState();
}

class _AdminOrdersViewState extends ConsumerState<_AdminOrdersView> {
  String _tierFilter = 'all';
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final ordersAsync = ref.watch(adminOrdersProvider((
      status: null,
      provider: null,
      tier: _tierFilter == 'all' ? null : _tierFilter,
      page: _page,
    )));

    return Column(
      children: [
        // Filter bar
        _AdminFilterBar(
          selectedTier: _tierFilter,
          onTierChanged: (tier) => setState(() {
            _tierFilter = tier;
            _page = 1;
          }),
        ),
        // Content
        Expanded(
          child: ordersAsync.when(
            data: (response) {
              if (response.items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: colors.textTertiary),
                      const SizedBox(height: 16),
                      Text('No orders found', style: TextStyle(color: colors.textSecondary)),
                    ],
                  ),
                );
              }
              final totalPages = response.meta?.totalPages ?? 1;
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: response.items.length,
                      itemBuilder: (context, index) {
                        final order = response.items[index];
                        return _AdminOrderTile(order: order);
                      },
                    ),
                  ),
                  if (totalPages > 1)
                    _AdminPagination(
                      page: _page,
                      totalPages: totalPages,
                      onPageChanged: (page) => setState(() => _page = page),
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 16),
                  Text('Failed to load orders', style: TextStyle(color: colors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(err.toString(), style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.invalidate(adminOrdersProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Admin AI Services View - integrated into main content area
class _AdminAIServicesView extends ConsumerStatefulWidget {
  const _AdminAIServicesView();

  @override
  ConsumerState<_AdminAIServicesView> createState() => _AdminAIServicesViewState();
}

class _AdminAIServicesViewState extends ConsumerState<_AdminAIServicesView> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final configsAsync = ref.watch(aiConfigsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.psychology_outlined, size: 24, color: colors.primary),
              const SizedBox(width: 12),
              Text(
                'AI Services Configuration',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: configsAsync.when(
            data: (configs) => _buildConfigsList(colors, configs),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 12),
                  Text('Failed to load AI configs', style: TextStyle(color: colors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(err.toString(), style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigsList(FlowColorScheme colors, List<AIPromptConfig> configs) {
    if (configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text('No AI configurations found', style: TextStyle(color: colors.textSecondary)),
          ],
        ),
      );
    }

    return ListView(
      children: [
        // Help toggle
        InkWell(
          onTap: () => setState(() => _showHelp = !_showHelp),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _showHelp ? Icons.help : Icons.help_outline,
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Formatting Guidelines',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showHelp ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
        // Help section
        if (_showHelp) _buildHelpSection(colors),
        // Config items
        ...configs.map((config) => _AdminAIConfigTile(
          config: config,
          onTap: () => _showEditDialog(config),
        )),
      ],
    );
  }

  Widget _buildHelpSection(FlowColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Text(
                'Safe to use:',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              "• Plain text and numbers\n"
              "• Single quotes: 'example'\n"
              "• Parentheses: (like this)",
              style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Text(
                'Avoid if possible:',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              '• Double quotes: "\n'
              '• Curly braces: { }\n'
              '• Square brackets: [ ]',
              style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(AIPromptConfig config) {
    showDialog(
      context: context,
      builder: (context) => _AdminEditAIConfigDialog(config: config),
    ).then((updated) {
      if (updated == true) {
        ref.invalidate(aiConfigsProvider);
      }
    });
  }
}

/// AI Config tile for admin view
class _AdminAIConfigTile extends StatelessWidget {
  final AIPromptConfig config;
  final VoidCallback onTap;

  const _AdminAIConfigTile({required this.config, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.tune, size: 16, color: Colors.purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.displayName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.value.length > 60
                        ? '${config.value.substring(0, 60)}...'
                        : config.value,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Edit AI config dialog for admin view
class _AdminEditAIConfigDialog extends ConsumerStatefulWidget {
  final AIPromptConfig config;

  const _AdminEditAIConfigDialog({required this.config});

  @override
  ConsumerState<_AdminEditAIConfigDialog> createState() => _AdminEditAIConfigDialogState();
}

class _AdminEditAIConfigDialogState extends ConsumerState<_AdminEditAIConfigDialog> {
  late TextEditingController _valueController;
  bool _isLoading = false;
  String? _error;

  static const Map<String, String> _defaults = {
    'clean_title_instruction': 'Concise, action-oriented title (max 10 words)',
    'summary_instruction': 'Brief summary if description is long (max 20 words)',
    'complexity_instruction': "1-10 scale (1=trivial like 'buy milk', 10=complex multi-step project)",
    'due_date_instruction': "ISO 8601 date if mentioned (e.g., 'tomorrow' = next day, 'next week' = next Monday)",
    'decompose_step_count': '2-5',
  };

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: widget.config.value);
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _resetToDefault() {
    final defaultValue = _defaults[widget.config.key];
    if (defaultValue != null) {
      _valueController.text = defaultValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        widget.config.displayName,
        style: TextStyle(color: colors.textPrimary, fontSize: 18),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.config.description != null) ...[
              Text(
                widget.config.description!,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Value',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                if (_defaults.containsKey(widget.config.key))
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: Icon(Icons.restore, size: 14, color: colors.primary),
                    label: Text('Reset', style: TextStyle(fontSize: 12, color: colors.primary)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _valueController,
              maxLines: 4,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter value...',
                hintStyle: TextStyle(color: colors.textTertiary),
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.primary),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: FilledButton.styleFrom(backgroundColor: colors.primary),
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _saveChanges() async {
    final value = _valueController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Value cannot be empty');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final aiConfigActions = ref.read(aiConfigActionsProvider);
      await aiConfigActions.update(widget.config.key, value);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

/// Filter bar for admin views
class _AdminFilterBar extends StatelessWidget {
  final String selectedTier;
  final ValueChanged<String> onTierChanged;

  const _AdminFilterBar({
    required this.selectedTier,
    required this.onTierChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Text('Filter:', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
          const SizedBox(width: 12),
          _AdminFilterChip(label: 'All', isSelected: selectedTier == 'all', onTap: () => onTierChanged('all')),
          const SizedBox(width: 8),
          _AdminFilterChip(label: 'Free', isSelected: selectedTier == 'free', onTap: () => onTierChanged('free')),
          const SizedBox(width: 8),
          _AdminFilterChip(label: 'Light', isSelected: selectedTier == 'light', onTap: () => onTierChanged('light'), color: Colors.blue),
          const SizedBox(width: 8),
          _AdminFilterChip(label: 'Premium', isSelected: selectedTier == 'premium', onTap: () => onTierChanged('premium'), color: Colors.purple),
        ],
      ),
    );
  }
}

/// Filter chip for admin
class _AdminFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _AdminFilterChip({required this.label, required this.isSelected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final chipColor = color ?? colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withAlpha(38) : colors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? chipColor : colors.border, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : colors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// User tile for admin
class _AdminUserTile extends StatelessWidget {
  final AdminUser user;
  final VoidCallback onTap;

  const _AdminUserTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider.withAlpha(128), width: 0.5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _getTierColor(user.tier).withAlpha(51),
              child: Text(
                (user.name ?? user.email).substring(0, 1).toUpperCase(),
                style: TextStyle(fontSize: 14, color: _getTierColor(user.tier), fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.name ?? 'No name',
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _AdminTierBadge(tier: user.tier),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(user.email, style: TextStyle(color: colors.textTertiary, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${user.taskCount}', style: TextStyle(color: colors.textTertiary, fontSize: 12)),
            const SizedBox(width: 4),
            Icon(Icons.task_alt, size: 14, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'premium': return Colors.purple;
      case 'light': return Colors.blue;
      default: return Colors.grey;
    }
  }
}

/// Order tile for admin
class _AdminOrderTile extends StatelessWidget {
  final Order order;

  const _AdminOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final dateFormat = DateFormat('MMM d, HH:mm');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider.withAlpha(128), width: 0.5)),
      ),
      child: Row(
        children: [
          _AdminOrderStatusIcon(status: order.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.userEmail ?? order.userId.substring(0, 8),
                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '\$${order.amount.toStringAsFixed(2)}',
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(child: Text(order.planName ?? order.planId, style: TextStyle(color: colors.textTertiary, fontSize: 12))),
                    Text(dateFormat.format(order.createdAt), style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status icon for orders
class _AdminOrderStatusIcon extends StatelessWidget {
  final String status;

  const _AdminOrderStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case 'completed':
        color = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case 'pending':
        color = Colors.orange;
        icon = Icons.schedule;
        break;
      case 'failed':
        color = Colors.red;
        icon = Icons.error_outline;
        break;
      case 'refunded':
        color = Colors.blue;
        icon = Icons.replay;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Icon(icon, size: 20, color: color);
  }
}

/// Tier badge for admin
class _AdminTierBadge extends StatelessWidget {
  final String tier;

  const _AdminTierBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (tier) {
      case 'premium':
        color = Colors.purple;
        label = 'Pro';
        break;
      case 'light':
        color = Colors.blue;
        label = 'Light';
        break;
      default:
        color = Colors.grey;
        label = 'Free';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

/// Pagination for admin
class _AdminPagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const _AdminPagination({required this.page, required this.totalPages, required this.onPageChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
            icon: Icon(Icons.chevron_left, color: colors.textSecondary),
            iconSize: 20,
          ),
          Text('$page / $totalPages', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          IconButton(
            onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
            icon: Icon(Icons.chevron_right, color: colors.textSecondary),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}

/// Edit user dialog for admin
class _AdminEditUserDialog extends ConsumerStatefulWidget {
  final AdminUser user;

  const _AdminEditUserDialog({required this.user});

  @override
  ConsumerState<_AdminEditUserDialog> createState() => _AdminEditUserDialogState();
}

class _AdminEditUserDialogState extends ConsumerState<_AdminEditUserDialog> {
  late String _selectedTier;
  String? _selectedPlanId;
  DateTime? _startsAt;
  DateTime? _expiresAt;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.user.tier;
    _selectedPlanId = widget.user.planId;
    _startsAt = widget.user.subscribedAt ?? DateTime.now();
    _expiresAt = widget.user.expiresAt;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final plans = ref.watch(subscriptionPlansProvider);

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text('Edit Subscription', style: TextStyle(color: colors.textPrimary, fontSize: 18)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.withAlpha(51),
                  child: Text((widget.user.name ?? widget.user.email).substring(0, 1).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user.name ?? 'No name', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500)),
                      Text(widget.user.email, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colors.error.withAlpha(26), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
              ),
              const SizedBox(height: 12),
            ],

            // Plan selection
            Text('Plan', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            plans.when(
              data: (planList) => Container(
                decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedPlanId,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    hint: const Text('Select plan'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Free (no plan)')),
                      ...planList.where((p) => !p.isFree).map((plan) => DropdownMenuItem(
                        value: plan.id,
                        child: Text('${plan.name} - ${plan.formattedPrice}'),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedPlanId = value;
                        if (value == null) {
                          _selectedTier = 'free';
                        } else {
                          final plan = planList.firstWhere((p) => p.id == value);
                          _selectedTier = plan.tier;
                        }
                      });
                    },
                  ),
                ),
              ),
              loading: () => const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => Text('Failed to load plans', style: TextStyle(color: colors.error)),
            ),

            if (_selectedPlanId != null) ...[
              const SizedBox(height: 16),
              Text('Starts', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _selectStartDate,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_startsAt != null ? DateFormat('MMM d, yyyy').format(_startsAt!) : 'Today', style: TextStyle(color: colors.textPrimary, fontSize: 14))),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Text('Expires', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _selectExpirationDate,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_expiresAt != null ? DateFormat('MMM d, yyyy').format(_expiresAt!) : 'No expiration', style: TextStyle(color: colors.textPrimary, fontSize: 14))),
                      if (_expiresAt != null)
                        GestureDetector(
                          onTap: () => setState(() => _expiresAt = null),
                          child: Icon(Icons.clear, size: 16, color: colors.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveChanges,
          style: FilledButton.styleFrom(backgroundColor: colors.primary),
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _startsAt = date);
  }

  Future<void> _selectExpirationDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) setState(() => _expiresAt = date);
  }

  Future<void> _saveChanges() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final tasksService = ref.read(tasksServiceProvider);
      await tasksService.updateUserSubscription(
        widget.user.id,
        tier: _selectedTier,
        planId: _selectedPlanId,
        startsAt: _startsAt,
        expiresAt: _expiresAt,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }
}
