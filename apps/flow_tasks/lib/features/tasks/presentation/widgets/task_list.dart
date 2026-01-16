import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/expandable_task_tile.dart';

enum TaskListType { today, next7days, all, trash, list, inbox, upcoming, completed }

class TaskList extends ConsumerWidget {
  final TaskListType type;

  const TaskList({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get tasks from local store (instant, includes optimistic updates)
    final tasks = _getTasksList(ref);

    if (tasks.isEmpty) {
      return _buildEmptyState();
    }

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
