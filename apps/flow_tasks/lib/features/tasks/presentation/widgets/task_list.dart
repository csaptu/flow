import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_tile.dart';

enum TaskListType { inbox, today, upcoming, completed }

class TaskList extends ConsumerWidget {
  final TaskListType type;

  const TaskList({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = _getTasksProvider(ref);

    return tasksAsync.when(
      data: (tasks) {
        if (tasks.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return TaskTile(
              task: task,
              onComplete: () => _completeTask(ref, task),
              onUncomplete: () => _uncompleteTask(ref, task),
              onTap: () => _openTaskDetail(context, task),
            );
          },
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
              onPressed: () => ref.invalidate(_getProviderType()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  AsyncValue<List<Task>> _getTasksProvider(WidgetRef ref) {
    switch (type) {
      case TaskListType.inbox:
        return ref.watch(inboxTasksProvider);
      case TaskListType.today:
        return ref.watch(todayTasksProvider);
      case TaskListType.upcoming:
        return ref.watch(upcomingTasksProvider);
      case TaskListType.completed:
        return ref.watch(tasksProvider); // TODO: Use completedTasksProvider
    }
  }

  ProviderOrFamily _getProviderType() {
    switch (type) {
      case TaskListType.inbox:
        return inboxTasksProvider;
      case TaskListType.today:
        return todayTasksProvider;
      case TaskListType.upcoming:
        return upcomingTasksProvider;
      case TaskListType.completed:
        return tasksProvider;
    }
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (type) {
      case TaskListType.inbox:
        icon = Icons.inbox_outlined;
        message = 'Your inbox is empty.\nAdd a task to get started.';
        break;
      case TaskListType.today:
        icon = Icons.wb_sunny_outlined;
        message = 'No tasks for today.\nEnjoy your free time!';
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

  Future<void> _completeTask(WidgetRef ref, Task task) async {
    final service = ref.read(tasksServiceProvider);
    await service.complete(task.id);
    ref.invalidate(_getProviderType());
  }

  Future<void> _uncompleteTask(WidgetRef ref, Task task) async {
    final service = ref.read(tasksServiceProvider);
    await service.uncomplete(task.id);
    ref.invalidate(_getProviderType());
  }

  void _openTaskDetail(BuildContext context, Task task) {
    // TODO: Navigate to task detail
  }
}
