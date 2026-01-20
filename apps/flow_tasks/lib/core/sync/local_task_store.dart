import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flow_models/flow_models.dart';
import 'sync_types.dart';

/// Local store for tasks with optimistic updates
///
/// This maintains a local cache of tasks that includes:
/// - Tasks fetched from the server
/// - Optimistically created tasks (not yet synced)
/// - Optimistically updated tasks
/// - Optimistically deleted tasks (marked as deleted locally)
class LocalTaskStore extends StateNotifier<LocalTaskState> {
  LocalTaskStore() : super(const LocalTaskState());

  /// Public getter for current state (for sync engine)
  LocalTaskState get currentState => state;

  /// Initialize from local storage (call on app start)
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // On web, clear local storage on new browser session to start fresh
    // (localStorage persists across sessions, but we want fresh start)
    if (kIsWeb) {
      await prefs.remove('sync_operations');
      await prefs.remove('optimistic_tasks');
      await prefs.remove('deleted_task_ids');
      return; // Start with empty state
    }

    // For mobile: Load pending operations
    final opsJson = prefs.getStringList('sync_operations') ?? [];
    final operations = opsJson
        .map((json) => SyncOperation.fromJson(jsonDecode(json)))
        .toList();

    // Load optimistic tasks
    final tasksJson = prefs.getStringList('optimistic_tasks') ?? [];
    final optimisticTasks = <String, Task>{};
    for (final json in tasksJson) {
      final task = Task.fromJson(jsonDecode(json));
      optimisticTasks[task.id] = task;
    }

    // Load deleted task IDs
    final deletedIds = prefs.getStringList('deleted_task_ids')?.toSet() ?? {};

    state = state.copyWith(
      pendingOperations: operations,
      optimisticTasks: optimisticTasks,
      deletedTaskIds: deletedIds,
    );
  }

  /// Save state to local storage
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();

    // Save pending operations
    final opsJson = state.pendingOperations
        .map((op) => jsonEncode(op.toJson()))
        .toList();
    await prefs.setStringList('sync_operations', opsJson);

    // Save optimistic tasks
    final tasksJson = state.optimisticTasks.values
        .map((task) => jsonEncode(task.toJson()))
        .toList();
    await prefs.setStringList('optimistic_tasks', tasksJson);

    // Save deleted IDs
    await prefs.setStringList('deleted_task_ids', state.deletedTaskIds.toList());
  }

  /// Set tasks from server (initial load or refresh)
  void setServerTasks(List<Task> tasks) {
    final taskMap = <String, Task>{};
    for (final task in tasks) {
      taskMap[task.id] = task;
    }
    state = state.copyWith(serverTasks: taskMap);
  }

  /// Update a single task from server (e.g., after AI action)
  void updateTaskFromServer(Task task) {
    final newServer = Map<String, Task>.from(state.serverTasks);
    newServer[task.id] = task;

    // Also remove from optimistic if it exists there
    final newOptimistic = Map<String, Task>.from(state.optimisticTasks);
    newOptimistic.remove(task.id);

    state = state.copyWith(
      serverTasks: newServer,
      optimisticTasks: newOptimistic,
      incrementVersion: true,
    );
  }

  /// Update multiple tasks from server at once (e.g., after AI decompose)
  void updateTasksFromServer(List<Task> tasks) {
    if (tasks.isEmpty) return;

    final newServer = Map<String, Task>.from(state.serverTasks);
    final newOptimistic = Map<String, Task>.from(state.optimisticTasks);

    for (final task in tasks) {
      newServer[task.id] = task;
      newOptimistic.remove(task.id);
    }

    state = state.copyWith(
      serverTasks: newServer,
      optimisticTasks: newOptimistic,
      incrementVersion: true,
    );
  }

  /// Get merged task list (server + optimistic - deleted)
  List<Task> getMergedTasks() {
    final merged = <String, Task>{};

    // Start with server tasks
    merged.addAll(state.serverTasks);

    // Apply optimistic tasks (overwrite server versions)
    merged.addAll(state.optimisticTasks);

    // Remove deleted tasks
    for (final id in state.deletedTaskIds) {
      merged.remove(id);
    }

    return merged.values.toList();
  }

  /// Optimistically create a task
  Future<Task> createTask({
    required String title,
    String? description,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
    String? parentId,
  }) async {
    final now = DateTime.now();
    final taskId = generateClientId();

    // Create optimistic task
    final task = Task(
      id: taskId,
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority != null ? Priority.fromInt(priority) : Priority.none,
      tags: tags ?? [],
      parentId: parentId,
      depth: parentId != null ? 1 : 0,
      status: TaskStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    // Create sync operation
    final operation = SyncOperation.create(
      entityId: taskId,
      entityType: 'task',
      data: {
        'title': title,
        'description': description,
        'due_date': _formatDueDate(dueDate),
        'priority': priority,
        'tags': tags,
        'parent_id': parentId,
      },
    );

    // Update state
    state = state.copyWith(
      optimisticTasks: {...state.optimisticTasks, taskId: task},
      pendingOperations: [...state.pendingOperations, operation],
    );

    await _persist();
    return task;
  }

  /// Optimistically update a task
  Future<Task> updateTask(
    String taskId, {
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false, // Set to true to explicitly clear the date
    int? priority,
    String? status,
    List<String>? tags,
    bool? skipAutoCleanup,
    String? parentId, // Set to empty string to remove parent
  }) async {
    // Find existing task
    final existing = state.optimisticTasks[taskId] ?? state.serverTasks[taskId];
    if (existing == null) {
      throw Exception('Task not found: $taskId');
    }

    // Create updated task - handle nullable dueDate specially
    final updatedDueDate = clearDueDate ? null : (dueDate ?? existing.dueDate);
    final updated = Task(
      id: existing.id,
      title: title ?? existing.title,
      description: description ?? existing.description,
      aiSummary: existing.aiSummary,
      status: status != null ? TaskStatus.fromString(status) : existing.status,
      priority: priority != null ? Priority.fromInt(priority) : existing.priority,
      dueDate: updatedDueDate,
      completedAt: existing.completedAt,
      tags: tags ?? existing.tags,
      parentId: existing.parentId,
      depth: existing.depth,
      complexity: existing.complexity,
      hasChildren: existing.hasChildren,
      childrenCount: existing.childrenCount,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      originalTitle: existing.originalTitle,
      originalDescription: existing.originalDescription,
      skipAutoCleanup: skipAutoCleanup ?? existing.skipAutoCleanup,
    );

    // Create sync operation
    final operation = SyncOperation.update(
      entityId: taskId,
      entityType: 'task',
      data: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (dueDate != null) 'due_date': _formatDueDate(dueDate),
        if (clearDueDate) 'due_date': null, // Explicitly send null to clear
        if (priority != null) 'priority': priority,
        if (status != null) 'status': status,
        if (tags != null) 'tags': tags,
        if (parentId != null) 'parent_id': parentId,
      },
    );

    // Update state - increment version to ensure state change is detected
    state = state.copyWith(
      optimisticTasks: {...state.optimisticTasks, taskId: updated},
      pendingOperations: [...state.pendingOperations, operation],
      incrementVersion: true,
    );

    await _persist();
    return updated;
  }

  /// Optimistically complete a task
  Future<Task> completeTask(String taskId) async {
    return updateTask(taskId, status: 'completed');
  }

  /// Optimistically uncomplete a task
  Future<Task> uncompleteTask(String taskId) async {
    return updateTask(taskId, status: 'pending');
  }

  /// Optimistically delete a task
  Future<void> deleteTask(String taskId) async {
    // Create sync operation
    final operation = SyncOperation.delete(
      entityId: taskId,
      entityType: 'task',
    );

    // Update state - add to deleted set, remove from optimistic
    final newOptimistic = Map<String, Task>.from(state.optimisticTasks);
    newOptimistic.remove(taskId);

    state = state.copyWith(
      optimisticTasks: newOptimistic,
      deletedTaskIds: {...state.deletedTaskIds, taskId},
      pendingOperations: [...state.pendingOperations, operation],
    );

    await _persist();
  }

  /// Called when a sync operation succeeds
  void onSyncSuccess(String operationId, Task? serverTask) {
    final operation = state.pendingOperations
        .where((op) => op.id == operationId)
        .firstOrNull;

    if (operation == null) return;

    // Remove the operation from pending
    final newOperations = state.pendingOperations
        .where((op) => op.id != operationId)
        .toList();

    // Update based on operation type
    switch (operation.type) {
      case SyncOperationType.create:
        if (serverTask != null) {
          // Replace optimistic task with server version
          final newOptimistic = Map<String, Task>.from(state.optimisticTasks);
          newOptimistic.remove(operation.entityId);

          final newServer = Map<String, Task>.from(state.serverTasks);
          newServer[serverTask.id] = serverTask;

          state = state.copyWith(
            pendingOperations: newOperations,
            optimisticTasks: newOptimistic,
            serverTasks: newServer,
          );
        }
        break;

      case SyncOperationType.update:
        if (serverTask != null) {
          // Replace optimistic with server version
          final newOptimistic = Map<String, Task>.from(state.optimisticTasks);
          newOptimistic.remove(operation.entityId);

          final newServer = Map<String, Task>.from(state.serverTasks);
          newServer[serverTask.id] = serverTask;

          state = state.copyWith(
            pendingOperations: newOperations,
            optimisticTasks: newOptimistic,
            serverTasks: newServer,
          );
        }
        break;

      case SyncOperationType.delete:
        // Remove from deleted set and server tasks
        final newDeleted = Set<String>.from(state.deletedTaskIds);
        newDeleted.remove(operation.entityId);

        final newServer = Map<String, Task>.from(state.serverTasks);
        newServer.remove(operation.entityId);

        state = state.copyWith(
          pendingOperations: newOperations,
          deletedTaskIds: newDeleted,
          serverTasks: newServer,
        );
        break;
    }

    _persist();
  }

  /// Called when a sync operation fails
  void onSyncError(String operationId, String error) {
    final newOperations = state.pendingOperations.map((op) {
      if (op.id == operationId) {
        return op.copyWith(
          retryCount: op.retryCount + 1,
          error: error,
        );
      }
      return op;
    }).toList();

    state = state.copyWith(pendingOperations: newOperations);
    _persist();
  }

  /// Rollback a failed operation
  void rollback(String operationId) {
    final operation = state.pendingOperations
        .where((op) => op.id == operationId)
        .firstOrNull;

    if (operation == null) return;

    final newOperations = state.pendingOperations
        .where((op) => op.id != operationId)
        .toList();

    switch (operation.type) {
      case SyncOperationType.create:
        // Remove optimistic task
        final newOptimistic = Map<String, Task>.from(state.optimisticTasks);
        newOptimistic.remove(operation.entityId);
        state = state.copyWith(
          pendingOperations: newOperations,
          optimisticTasks: newOptimistic,
        );
        break;

      case SyncOperationType.update:
        // Revert to server version
        final newOptimistic = Map<String, Task>.from(state.optimisticTasks);
        newOptimistic.remove(operation.entityId);
        state = state.copyWith(
          pendingOperations: newOperations,
          optimisticTasks: newOptimistic,
        );
        break;

      case SyncOperationType.delete:
        // Restore task (remove from deleted set)
        final newDeleted = Set<String>.from(state.deletedTaskIds);
        newDeleted.remove(operation.entityId);
        state = state.copyWith(
          pendingOperations: newOperations,
          deletedTaskIds: newDeleted,
        );
        break;
    }

    _persist();
  }

  /// Clear all pending operations (use with caution)
  Future<void> clearPending() async {
    state = state.copyWith(
      pendingOperations: [],
      optimisticTasks: {},
      deletedTaskIds: {},
    );
    await _persist();
  }
}

/// State for local task store
class LocalTaskState {
  final Map<String, Task> serverTasks;
  final Map<String, Task> optimisticTasks;
  final Set<String> deletedTaskIds;
  final List<SyncOperation> pendingOperations;
  final int version; // Version counter to force state change detection

  const LocalTaskState({
    this.serverTasks = const {},
    this.optimisticTasks = const {},
    this.deletedTaskIds = const {},
    this.pendingOperations = const [],
    this.version = 0,
  });

  LocalTaskState copyWith({
    Map<String, Task>? serverTasks,
    Map<String, Task>? optimisticTasks,
    Set<String>? deletedTaskIds,
    List<SyncOperation>? pendingOperations,
    bool incrementVersion = false,
  }) {
    return LocalTaskState(
      serverTasks: serverTasks ?? this.serverTasks,
      optimisticTasks: optimisticTasks ?? this.optimisticTasks,
      deletedTaskIds: deletedTaskIds ?? this.deletedTaskIds,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      version: incrementVersion ? version + 1 : version,
    );
  }

  bool get hasPendingChanges => pendingOperations.isNotEmpty;
  int get pendingCount => pendingOperations.length;

  /// Check if a specific task has a pending create operation
  bool hasPendingCreate(String taskId) {
    return pendingOperations.any(
      (op) => op.entityId == taskId && op.type == SyncOperationType.create,
    );
  }
}

/// Format due date for API.
/// If the date has no specific time (midnight local), send it as local time to preserve the date.
/// If it has a specific time, send as UTC for accuracy.
String? _formatDueDate(DateTime? date) {
  if (date == null) return null;

  // Convert to local time to check if it's midnight
  final local = date.toLocal();
  final isDateOnly = local.hour == 0 && local.minute == 0 && local.second == 0;

  if (isDateOnly) {
    // Send as local midnight to preserve the date across timezones
    // Format: 2026-01-20T00:00:00+07:00 (with local offset)
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final dateStr = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    return '${dateStr}T00:00:00$sign$hours:$minutes';
  } else {
    // Has specific time - send as UTC for accuracy
    return date.toUtc().toIso8601String();
  }
}
