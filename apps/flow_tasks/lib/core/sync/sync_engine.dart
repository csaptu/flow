import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';
import 'sync_types.dart';
import 'local_task_store.dart';

/// Sync engine that processes pending operations
class SyncEngine {
  final TasksService _tasksService;
  final LocalTaskStore _localStore;
  final void Function(SyncState) _onStateChange;

  Timer? _syncTimer;
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = true;
  bool _isSyncing = false;
  Completer<void>? _syncCompleter;

  SyncEngine({
    required TasksService tasksService,
    required LocalTaskStore localStore,
    required void Function(SyncState) onStateChange,
  })  : _tasksService = tasksService,
        _localStore = localStore,
        _onStateChange = onStateChange;

  /// Start the sync engine
  void start() {
    // Skip connectivity monitoring on web - it triggers intrusive permission dialogs
    // Web browsers handle offline mode differently; we'll detect via API errors
    if (!kIsWeb) {
      // Listen to connectivity changes (mobile/desktop only)
      _connectivitySubscription = Connectivity()
          .onConnectivityChanged
          .listen(_onConnectivityChanged);

      // Check initial connectivity
      Connectivity().checkConnectivity().then((result) {
        _onConnectivityChanged(result);
      });
    }

    // Start periodic sync (every 30 seconds when online)
    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _syncIfNeeded(),
    );

    // Initial sync
    _syncIfNeeded();
  }

  /// Stop the sync engine
  void stop() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
  }

  void _onConnectivityChanged(ConnectivityResult result) {
    final wasOffline = !_isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (_isOnline && wasOffline) {
      // Just came online - sync immediately
      _syncIfNeeded();
    }

    _updateState();
  }

  void _updateState() {
    final state = _localStore.currentState;

    SyncStatus status;
    if (!_isOnline) {
      status = SyncStatus.offline;
    } else if (_isSyncing) {
      status = SyncStatus.syncing;
    } else if (state.hasPendingChanges) {
      status = SyncStatus.pending;
    } else {
      status = SyncStatus.synced;
    }

    _onStateChange(SyncState(
      status: status,
      pendingCount: state.pendingCount,
      lastSyncAt: DateTime.now(),
    ));
  }

  /// Sync if there are pending operations and we're online
  Future<void> _syncIfNeeded() async {
    if (!_isOnline) return;

    // If already syncing, wait for it to complete then check for more
    if (_isSyncing) {
      if (_syncCompleter != null) {
        await _syncCompleter!.future;
      }
      // After waiting, check if there are still pending ops to sync
      final stillPending = _localStore.currentState.pendingOperations;
      if (stillPending.isEmpty) return;
      // Recurse to sync remaining operations
      return _syncIfNeeded();
    }

    final pending = _localStore.currentState.pendingOperations;
    if (pending.isEmpty) return;

    _isSyncing = true;
    _syncCompleter = Completer<void>();
    _updateState();

    try {
      await _processPendingOperations();
    } finally {
      _isSyncing = false;
      _updateState();
      _syncCompleter?.complete();
      _syncCompleter = null;
    }
  }

  /// Process all pending operations
  Future<void> _processPendingOperations() async {
    final pending = List<SyncOperation>.from(_localStore.currentState.pendingOperations);

    for (final operation in pending) {
      // Skip operations that have failed too many times
      if (operation.retryCount >= 3) {
        continue;
      }

      try {
        await _processOperation(operation);
      } catch (e) {
        _localStore.onSyncError(operation.id, e.toString());
      }
    }
  }

  /// Process a single operation
  Future<void> _processOperation(SyncOperation operation) async {
    switch (operation.entityType) {
      case 'task':
        await _processTaskOperation(operation);
        break;
      default:
        throw Exception('Unknown entity type: ${operation.entityType}');
    }
  }

  /// Process task-specific operations
  Future<void> _processTaskOperation(SyncOperation operation) async {
    switch (operation.type) {
      case SyncOperationType.create:
        final task = await _tasksService.create(
          id: operation.entityId, // Send client ID for offline-first sync
          title: operation.data['title'] as String,
          description: operation.data['description'] as String?,
          dueAt: operation.data['due_at'] != null
              ? DateTime.parse(operation.data['due_at'] as String)
              : null,
          hasDueTime: operation.data['has_due_time'] as bool? ?? false,
          priority: operation.data['priority'] as int?,
          tags: (operation.data['tags'] as List?)?.cast<String>(),
          parentId: operation.data['parent_id'] as String?,
        );
        _localStore.onSyncSuccess(operation.id, task);
        break;

      case SyncOperationType.update:
        final task = await _tasksService.update(
          operation.entityId,
          title: operation.data['title'] as String?,
          description: operation.data['description'] as String?,
          dueAt: operation.data['due_at'] != null
              ? DateTime.parse(operation.data['due_at'] as String)
              : null,
          hasDueTime: operation.data['has_due_time'] as bool?,
          clearDueAt: operation.data['clear_due_at'] as bool? ?? false,
          priority: operation.data['priority'] as int?,
          status: operation.data['status'] as String?,
          tags: (operation.data['tags'] as List?)?.cast<String>(),
          parentId: operation.data['parent_id'] as String?,
        );
        _localStore.onSyncSuccess(operation.id, task);
        break;

      case SyncOperationType.delete:
        await _tasksService.delete(operation.entityId);
        _localStore.onSyncSuccess(operation.id, null);
        break;
    }
  }

  /// Force sync now
  Future<void> syncNow() async {
    await _syncIfNeeded();
  }

  /// Awaits until pending operations are synced.
  /// Simply calls syncNow() which already handles in-progress syncs properly.
  Future<void> awaitSync() async {
    if (!_isOnline) return;

    final pending = _localStore.currentState.pendingOperations;
    if (pending.isEmpty && !_isSyncing) return;

    // Just call syncNow and wait - it handles everything
    await syncNow();
  }

  /// Fetch latest from server and merge
  Future<void> refresh() async {
    if (!_isOnline) return;

    try {
      // Fetch all task lists
      final inbox = await _tasksService.getInbox();
      final today = await _tasksService.getToday();
      final upcoming = await _tasksService.getUpcoming();

      // Merge all tasks (removing duplicates by ID)
      final allTasks = <String, Task>{};
      for (final task in [...inbox, ...today, ...upcoming]) {
        allTasks[task.id] = task;
      }

      _localStore.setServerTasks(allTasks.values.toList());
    } catch (e) {
      // Ignore refresh errors - we still have local data
    }
  }
}
