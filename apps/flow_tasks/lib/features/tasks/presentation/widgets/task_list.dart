import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/expandable_task_tile.dart';
import 'package:intl/intl.dart';

enum TaskListType { today, next7days, all, trash, list, inbox, upcoming, completed }

/// Groups tasks by their due date category
class _DateGroup {
  final String title;
  final List<Task> tasks;
  final bool isOverdue;
  final bool isCollapsible;
  bool isExpanded;

  _DateGroup({
    required this.title,
    required this.tasks,
    this.isOverdue = false,
    this.isCollapsible = true,
    this.isExpanded = true,
  });
}

class TaskList extends ConsumerWidget {
  final TaskListType type;

  const TaskList({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = _getTasksList(ref);
    final groupByDate = ref.watch(groupByDateProvider);

    if (tasks.isEmpty) {
      return _buildEmptyState();
    }

    // Don't group for trash or completed views
    if (type == TaskListType.trash || type == TaskListType.completed || !groupByDate) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return ExpandableTaskTile(
            task: task,
            onComplete: () => _completeTask(ref, task),
            onUncomplete: () => _uncompleteTask(ref, task),
            onDelete: () => _moveToTrash(ref, task),
          );
        },
      );
    }

    // Group tasks by date
    final groups = _groupTasksByDate(tasks);

    return _GroupedTaskListView(
      groups: groups,
      type: type,
    );
  }

  List<_DateGroup> _groupTasksByDate(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Separate overdue tasks
    final overdueTasks = <Task>[];
    final todayTasks = <Task>[];
    final tomorrowTasks = <Task>[];
    final futureTasks = <String, List<Task>>{};
    final noDateTasks = <Task>[];

    for (final task in tasks) {
      if (task.isOverdue) {
        overdueTasks.add(task);
      } else if (task.dueDate == null) {
        noDateTasks.add(task);
      } else {
        final dueDate = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
        if (dueDate.isAtSameMomentAs(today)) {
          todayTasks.add(task);
        } else if (dueDate.isAtSameMomentAs(tomorrow)) {
          tomorrowTasks.add(task);
        } else {
          // Group by date string for future dates
          final dateKey = _formatGroupDate(task.dueDate!);
          futureTasks.putIfAbsent(dateKey, () => []).add(task);
        }
      }
    }

    final groups = <_DateGroup>[];

    // Overdue section always first
    if (overdueTasks.isNotEmpty) {
      overdueTasks.sort((a, b) => (a.dueDate ?? DateTime.now()).compareTo(b.dueDate ?? DateTime.now()));
      groups.add(_DateGroup(
        title: 'Overdue',
        tasks: overdueTasks,
        isOverdue: true,
      ));
    }

    // Today section
    if (todayTasks.isNotEmpty) {
      groups.add(_DateGroup(
        title: 'Today',
        tasks: todayTasks,
      ));
    }

    // Tomorrow section
    if (tomorrowTasks.isNotEmpty) {
      groups.add(_DateGroup(
        title: 'Tomorrow',
        tasks: tomorrowTasks,
      ));
    }

    // Future dates sorted by date
    final sortedFutureDates = futureTasks.keys.toList()
      ..sort((a, b) {
        final dateA = futureTasks[a]!.first.dueDate!;
        final dateB = futureTasks[b]!.first.dueDate!;
        return dateA.compareTo(dateB);
      });

    for (final dateKey in sortedFutureDates) {
      groups.add(_DateGroup(
        title: dateKey,
        tasks: futureTasks[dateKey]!,
      ));
    }

    // No date section at the end
    if (noDateTasks.isNotEmpty) {
      groups.add(_DateGroup(
        title: 'No Date',
        tasks: noDateTasks,
      ));
    }

    return groups;
  }

  String _formatGroupDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final daysFromToday = dateOnly.difference(today).inDays;

    if (daysFromToday < 7) {
      // Within this week - show weekday name
      return DateFormat('EEEE').format(date);
    } else if (daysFromToday < 14) {
      // Next week
      return 'Next ${DateFormat('EEEE').format(date)}';
    } else {
      // Further out - show full date
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  List<Task> _getTasksList(WidgetRef ref) {
    switch (type) {
      case TaskListType.today:
        return ref.watch(todayTasksProvider);
      case TaskListType.next7days:
        return ref.watch(next7DaysTasksProvider);
      case TaskListType.all:
        return ref.watch(allTasksProvider);
      case TaskListType.trash:
        return ref.watch(trashTasksProvider);
      case TaskListType.list:
        // List tasks are handled separately
        return [];
      case TaskListType.inbox:
        return ref.watch(inboxTasksProvider);
      case TaskListType.upcoming:
        return ref.watch(upcomingTasksProvider);
      case TaskListType.completed:
        return ref.watch(completedTasksProvider);
    }
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (type) {
      case TaskListType.today:
        icon = Icons.wb_sunny_outlined;
        message = 'No tasks for today.\nEnjoy your free time!';
        break;
      case TaskListType.next7days:
        icon = Icons.date_range_outlined;
        message = 'No tasks in the next 7 days.\nPlan ahead by adding due dates.';
        break;
      case TaskListType.all:
        icon = Icons.inbox_outlined;
        message = 'No tasks yet.\nAdd a task to get started.';
        break;
      case TaskListType.trash:
        icon = Icons.delete_outline;
        message = 'Trash is empty.';
        break;
      case TaskListType.list:
        icon = Icons.tag;
        message = 'No tasks in this list.';
        break;
      case TaskListType.inbox:
        icon = Icons.inbox_outlined;
        message = 'Your inbox is empty.\nAdd a task to get started.';
        break;
      case TaskListType.upcoming:
        icon = Icons.calendar_today_outlined;
        message = 'No upcoming tasks.\nPlan ahead by adding due dates.';
        break;
      case TaskListType.completed:
        icon = Icons.check_circle_outline;
        message = 'No completed tasks yet.\nGet started by finishing something!';
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// Complete task - instant UI update
  Future<void> _completeTask(WidgetRef ref, Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.complete(task.id);
  }

  /// Uncomplete task - instant UI update
  Future<void> _uncompleteTask(WidgetRef ref, Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.uncomplete(task.id);
  }

  /// Move task to trash - instant UI update
  Future<void> _moveToTrash(WidgetRef ref, Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.update(task.id, status: 'cancelled');
  }

  void _openTaskDetail(WidgetRef ref, Task task) {
    ref.read(selectedTaskIdProvider.notifier).state = task.id;
  }
}

/// Grouped task list view with collapsible sections
class _GroupedTaskListView extends ConsumerStatefulWidget {
  final List<_DateGroup> groups;
  final TaskListType type;

  const _GroupedTaskListView({
    required this.groups,
    required this.type,
  });

  @override
  ConsumerState<_GroupedTaskListView> createState() => _GroupedTaskListViewState();
}

class _GroupedTaskListViewState extends ConsumerState<_GroupedTaskListView> {
  late Map<String, bool> _expandedState;

  @override
  void initState() {
    super.initState();
    _expandedState = {
      for (final group in widget.groups) group.title: true,
    };
  }

  @override
  void didUpdateWidget(covariant _GroupedTaskListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Add new groups to expanded state
    for (final group in widget.groups) {
      _expandedState.putIfAbsent(group.title, () => true);
    }
  }

  void _toggleGroup(String title) {
    setState(() {
      _expandedState[title] = !(_expandedState[title] ?? true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.groups.length,
      itemBuilder: (context, groupIndex) {
        final group = widget.groups[groupIndex];
        final isExpanded = _expandedState[group.title] ?? true;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header
            InkWell(
              onTap: () => _toggleGroup(group.title),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 20,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      group.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: group.isOverdue ? colors.error : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${group.tasks.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Task items (only if expanded)
            if (isExpanded)
              ...group.tasks.map((task) => ExpandableTaskTile(
                task: task,
                onComplete: () => _completeTask(task),
                onUncomplete: () => _uncompleteTask(task),
                onDelete: () => _moveToTrash(task),
              )),
          ],
        );
      },
    );
  }

  Future<void> _completeTask(Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.complete(task.id);
  }

  Future<void> _uncompleteTask(Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.uncomplete(task.id);
  }

  Future<void> _moveToTrash(Task task) async {
    final actions = ref.read(taskActionsProvider);
    await actions.update(task.id, status: 'cancelled');
  }
}
