import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flow_tasks/core/auth/google_sign_in_stub.dart'
    if (dart.library.html) 'package:flow_tasks/core/auth/google_sign_in_web_helper.dart';
import 'package:flow_tasks/core/sync/sync_types.dart';
import 'package:flow_tasks/core/sync/local_task_store.dart';
import 'package:flow_tasks/core/sync/sync_engine.dart';

const _googleClientId = '868169256843-ke0firpbckajqd06adpdc2a1rgo14ejt.apps.googleusercontent.com';

// API Client
final apiClientProvider = Provider<FlowApiClient>((ref) {
  // In development, use localhost with correct ports for each service
  // In production, these would be environment variables or a single gateway URL
  const sharedUrl = String.fromEnvironment(
    'SHARED_API_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );
  const tasksUrl = String.fromEnvironment(
    'TASKS_API_URL',
    defaultValue: 'http://localhost:8081/api/v1',
  );
  const projectsUrl = String.fromEnvironment(
    'PROJECTS_API_URL',
    defaultValue: 'http://localhost:8082/api/v1',
  );

  return FlowApiClient(
    config: ApiConfig(
      sharedServiceUrl: sharedUrl,
      tasksServiceUrl: tasksUrl,
      projectsServiceUrl: projectsUrl,
    ),
  );
});

// Services
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider));
});

final tasksServiceProvider = Provider<TasksService>((ref) {
  return TasksService(ref.watch(apiClientProvider));
});

// Local task store for optimistic updates
final localTaskStoreProvider =
    StateNotifierProvider<LocalTaskStore, LocalTaskState>((ref) {
  return LocalTaskStore();
});

// Sync state
final syncStateProvider = StateProvider<SyncState>((ref) {
  return const SyncState();
});

// Sync engine
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final tasksService = ref.watch(tasksServiceProvider);
  final localStore = ref.watch(localTaskStoreProvider.notifier);
  final syncStateNotifier = ref.watch(syncStateProvider.notifier);

  return SyncEngine(
    tasksService: tasksService,
    localStore: localStore,
    onStateChange: (state) => syncStateNotifier.state = state,
  );
});

// Initialization
final initializationProvider = FutureProvider<void>((ref) async {
  final client = ref.watch(apiClientProvider);
  await client.init();
});

// Connectivity / Online status
final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Returns true if the device has network connectivity
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (result) => result != ConnectivityResult.none,
    loading: () => true, // Assume online while loading
    error: (_, __) => true, // Assume online on error
  );
});

// Theme mode
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'system';
    state = _parseThemeMode(mode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  ThemeMode _parseThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

// =====================================================
// Timezone Provider
// =====================================================

/// User's timezone setting
/// null means use device timezone (default)
final userTimezoneProvider = StateNotifierProvider<UserTimezoneNotifier, String?>((ref) {
  return UserTimezoneNotifier();
});

class UserTimezoneNotifier extends StateNotifier<String?> {
  UserTimezoneNotifier() : super(null) {
    _loadTimezone();
  }

  Future<void> _loadTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    final tz = prefs.getString('user_timezone');
    state = tz; // null means device timezone
  }

  /// Get the effective timezone (user's choice or device default)
  String get effectiveTimezone {
    return state ?? DateTime.now().timeZoneName;
  }

  /// Get the timezone offset in hours
  int get offsetHours {
    return DateTime.now().timeZoneOffset.inHours;
  }

  /// Set timezone and optionally refresh due dates
  /// Returns true if timezone was changed
  Future<bool> setTimezone(String? timezone) async {
    final previousTimezone = state;
    if (previousTimezone == timezone) return false;

    state = timezone;
    final prefs = await SharedPreferences.getInstance();
    if (timezone == null) {
      await prefs.remove('user_timezone');
    } else {
      await prefs.setString('user_timezone', timezone);
    }
    return true;
  }
}

/// Common timezone options for the picker
class TimezoneOption {
  final String id;
  final String label;
  final String offset;

  const TimezoneOption(this.id, this.label, this.offset);
}

/// List of common timezones
const commonTimezones = [
  TimezoneOption('device', 'Device Default', 'Auto'),
  TimezoneOption('UTC', 'UTC', '+00:00'),
  TimezoneOption('America/New_York', 'Eastern Time (US)', '-05:00'),
  TimezoneOption('America/Chicago', 'Central Time (US)', '-06:00'),
  TimezoneOption('America/Denver', 'Mountain Time (US)', '-07:00'),
  TimezoneOption('America/Los_Angeles', 'Pacific Time (US)', '-08:00'),
  TimezoneOption('Europe/London', 'London', '+00:00'),
  TimezoneOption('Europe/Paris', 'Paris', '+01:00'),
  TimezoneOption('Europe/Berlin', 'Berlin', '+01:00'),
  TimezoneOption('Asia/Tokyo', 'Tokyo', '+09:00'),
  TimezoneOption('Asia/Shanghai', 'Shanghai', '+08:00'),
  TimezoneOption('Asia/Singapore', 'Singapore', '+08:00'),
  TimezoneOption('Asia/Ho_Chi_Minh', 'Ho Chi Minh City', '+07:00'),
  TimezoneOption('Asia/Bangkok', 'Bangkok', '+07:00'),
  TimezoneOption('Australia/Sydney', 'Sydney', '+11:00'),
  TimezoneOption('Pacific/Auckland', 'Auckland', '+13:00'),
];

// Auth state
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>(
  (ref) => AuthStateNotifier(ref),
);

enum AuthStatus { initial, authenticated, unauthenticated, loading }

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthStateNotifier(this._ref) : super(const AuthState());

  Future<void> checkAuth() async {
    state = state.copyWith(status: AuthStatus.loading);

    final client = _ref.read(apiClientProvider);
    if (!client.isAuthenticated) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final authService = _ref.read(authServiceProvider);
      final user = await authService.getCurrentUser();
      state = state.copyWith(status: AuthStatus.authenticated, user: user);
    } catch (e) {
      // Clear invalid tokens from storage
      await client.logout();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final authService = _ref.read(authServiceProvider);
      final response = await authService.login(email: email, password: password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: response.user,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Start registration - sends verification code to email
  /// Returns expires_in (seconds)
  Future<int> startRegistration(String email, String password, String name) async {
    final authService = _ref.read(authServiceProvider);
    return await authService.register(
      email: email,
      password: password,
      name: name,
    );
  }

  /// Complete registration after email verification
  Future<void> completeRegistration(String email, String code) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final authService = _ref.read(authServiceProvider);
      final response = await authService.verifyRegistration(
        email: email,
        code: code,
      );
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: response.user,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Resend verification code for pending registration
  Future<int> resendVerificationCode(String email) async {
    final authService = _ref.read(authServiceProvider);
    return await authService.resendVerificationCode(email);
  }

  Future<void> devLogin(String email) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final authService = _ref.read(authServiceProvider);
      final response = await authService.devLogin(email: email);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: response.user,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> loginWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      String? idToken;

      if (kIsWeb) {
        // Use Google Identity Services on web
        idToken = await GoogleSignInWebHelper.signIn();
      } else {
        // Use google_sign_in package on mobile/desktop
        // serverClientId ensures the ID token's audience matches what the server expects
        final googleSignIn = GoogleSignIn(
          scopes: ['email', 'profile'],
          serverClientId: _googleClientId, // Web client ID - server validates against this
        );

        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          state = state.copyWith(status: AuthStatus.unauthenticated);
          return;
        }

        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
      }

      if (idToken == null) {
        state = state.copyWith(status: AuthStatus.unauthenticated);
        throw Exception('Failed to get Google ID token. Please try again.');
      }

      final authService = _ref.read(authServiceProvider);
      final response = await authService.loginWithGoogle(idToken);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: response.user,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    final authService = _ref.read(authServiceProvider);
    await authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> updateProfile({String? name, String? avatarUrl}) async {
    final authService = _ref.read(authServiceProvider);
    final updatedUser = await authService.updateProfile(
      name: name,
      avatarUrl: avatarUrl,
    );
    state = state.copyWith(user: updatedUser);
  }

  /// Request password reset email
  /// Note: For security, this always succeeds silently (doesn't reveal if email exists)
  Future<void> requestPasswordReset(String email) async {
    final authService = _ref.read(authServiceProvider);
    await authService.forgotPassword(email);
  }
}

// Tasks providers - use optimistic local store with server fetch

/// Fetches tasks from server and updates local store
/// Exposed for manual refresh triggers (e.g., after AI action revert)
final tasksFetchProvider = FutureProvider.autoDispose<void>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return;

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return;

  final service = ref.watch(tasksServiceProvider);
  final localStore = ref.watch(localTaskStoreProvider.notifier);

  // Fetch and store - get all tasks (large page size to avoid pagination issues)
  final response = await service.list(pageSize: 1000);
  localStore.setServerTasks(response.items);
});

/// All tasks (merged optimistic + server)
final tasksProvider = Provider<List<Task>>((ref) {
  // Trigger server fetch
  ref.watch(tasksFetchProvider);

  // Watch state to rebuild when it changes - use the state value directly
  final localState = ref.watch(localTaskStoreProvider);

  // Get merged tasks from state (server + optimistic - deleted)
  final merged = <String, Task>{};
  merged.addAll(localState.serverTasks);
  merged.addAll(localState.optimisticTasks);
  for (final id in localState.deletedTaskIds) {
    merged.remove(id);
  }
  return merged.values.toList();
});

/// All tasks (root-level only, sorted by createdAt descending)
/// Optionally includes completed tasks based on showCompletedTasksProvider
final allTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final showCompleted = ref.watch(showCompletedTasksProvider);
  final filtered = tasks
      .where((t) =>
          (showCompleted || t.status != TaskStatus.completed) &&
          t.status != TaskStatus.cancelled &&
          t.parentId == null) // Exclude subtasks
      .toList();
  // Sort by createdAt descending (latest first), completed tasks at end
  filtered.sort((a, b) {
    // Completed tasks go to the end
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return filtered;
});

/// Legacy inbox provider for backward compatibility
final inboxTasksProvider = Provider<List<Task>>((ref) {
  return ref.watch(allTasksProvider);
});

/// Today's tasks (includes overdue + tasks with no date, root-level only)
/// Optionally includes completed tasks based on showCompletedTasksProvider
final todayTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final showCompleted = ref.watch(showCompletedTasksProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  final filtered = tasks.where((t) {
    if (t.status == TaskStatus.cancelled) return false;
    if (!showCompleted && t.status == TaskStatus.completed) return false;
    if (t.parentId != null) return false; // Exclude subtasks
    // Include tasks with no due date
    if (t.dueAt == null) return true;
    final dueDate = DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day);
    // Include overdue (before today) OR due today
    return dueDate.isBefore(tomorrow);
  }).toList();
  // Sort: completed tasks at end, then by due date
  filtered.sort((a, b) {
    // Completed tasks go to the end
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;
    if (a.dueAt == null && b.dueAt == null) return 0;
    if (a.dueAt == null) return 1;
    if (b.dueAt == null) return -1;
    return a.dueAt!.compareTo(b.dueAt!);
  });
  return filtered;
});

/// Next 7 days tasks (includes overdue + next 7 days + tasks with no date, root-level only)
/// Optionally includes completed tasks based on showCompletedTasksProvider
final next7DaysTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final showCompleted = ref.watch(showCompletedTasksProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final in7Days = today.add(const Duration(days: 7));

  final filtered = tasks.where((t) {
    if (t.status == TaskStatus.cancelled) return false;
    if (!showCompleted && t.status == TaskStatus.completed) return false;
    if (t.parentId != null) return false; // Exclude subtasks
    // Include tasks with no due date
    if (t.dueAt == null) return true;
    final dueDate = DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day);
    // Include overdue (before today) OR within next 7 days
    return dueDate.isBefore(in7Days);
  }).toList();
  // Sort: completed tasks at end, then by due date
  filtered.sort((a, b) {
    // Completed tasks go to the end
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;
    if (a.dueAt == null && b.dueAt == null) return 0;
    if (a.dueAt == null) return 1;
    if (b.dueAt == null) return -1;
    return a.dueAt!.compareTo(b.dueAt!);
  });
  return filtered;
});

/// Legacy upcoming provider for backward compatibility
final upcomingTasksProvider = Provider<List<Task>>((ref) {
  return ref.watch(next7DaysTasksProvider);
});

/// Completed tasks (root-level only)
final completedTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  return tasks
      .where((t) => t.status == TaskStatus.completed && t.parentId == null)
      .toList();
});

/// Trash tasks (cancelled, root-level only)
final trashTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final filtered = tasks
      .where((t) => t.status == TaskStatus.cancelled && t.parentId == null)
      .toList();
  // Sort by updatedAt descending (most recently deleted first)
  filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return filtered;
});

// Task actions - optimistic updates
class TaskActions {
  final Ref _ref;

  TaskActions(this._ref);

  LocalTaskStore get _store => _ref.read(localTaskStoreProvider.notifier);
  SyncEngine get _syncEngine => _ref.read(syncEngineProvider);
  TasksService get _service => _ref.read(tasksServiceProvider);

  /// Create a task (instant, syncs in background)
  Future<Task> create({
    required String title,
    String? description,
    DateTime? dueAt,
    bool hasDueTime = false,
    int? priority,
    List<String>? tags,
    String? parentId,
  }) async {
    // Ensure AI preferences are loaded before checking the setting
    await _ref.read(aiPreferencesProvider.notifier).ensureLoaded();

    // Check if auto cleanup is disabled by user preference
    final shouldAutoClean = _ref.read(shouldAutoRunProvider(AIFeature.cleanTitle));

    final task = await _store.createTask(
      title: title,
      description: description,
      dueAt: dueAt,
      hasDueTime: hasDueTime,
      priority: priority,
      tags: tags,
      parentId: parentId,
      skipAutoCleanup: !shouldAutoClean,
    );

    // Sync in background - lists are derived from tasks dynamically
    _syncEngine.syncNow();

    return task;
  }

  /// Update a task (instant, syncs in background)
  /// Set clearDueAt to true to remove the due date entirely
  Future<Task> update(
    String taskId, {
    String? title,
    String? description,
    DateTime? dueAt,
    bool? hasDueTime,
    bool clearDueAt = false, // Set to true to explicitly clear the date
    int? priority,
    String? status,
    List<String>? tags,
    bool? skipAutoCleanup,
    String? parentId, // Set to empty string to remove parent
  }) async {
    final task = await _store.updateTask(
      taskId,
      title: title,
      description: description,
      dueAt: dueAt,
      hasDueTime: hasDueTime,
      clearDueAt: clearDueAt,
      priority: priority,
      status: status,
      tags: tags,
      skipAutoCleanup: skipAutoCleanup,
      parentId: parentId,
    );

    // Sync in background - lists are now derived from tasks dynamically
    _syncEngine.syncNow();

    // Refresh smart lists when status changes (affects entity counts)
    if (status != null) {
      _ref.invalidate(smartListsProvider);
    }

    // Note: Don't invalidate tasksFetchProvider for due date/time changes.
    // The optimistic update already has correct data. Invalidating immediately
    // causes a race condition where stale server data overwrites the optimistic
    // task after sync completes (server fetch returns before sync, then
    // setServerTasks overwrites the synced data with stale list response).

    return task;
  }

  /// Complete a task (instant)
  Future<Task> complete(String taskId) async {
    final task = await _store.completeTask(taskId);
    _syncEngine.syncNow();
    // Refresh smart lists (completed tasks are excluded from counts)
    _ref.invalidate(smartListsProvider);
    return task;
  }

  /// Uncomplete a task (instant)
  Future<Task> uncomplete(String taskId) async {
    final task = await _store.uncompleteTask(taskId);
    _syncEngine.syncNow();
    // Refresh smart lists (task is back in active counts)
    _ref.invalidate(smartListsProvider);
    return task;
  }

  /// Delete a task (instant)
  Future<void> delete(String taskId) async {
    await _store.deleteTask(taskId);
    _syncEngine.syncNow();
    // Refresh smart lists to update entity counts
    _ref.invalidate(smartListsProvider);
  }

  /// Merge two entities (e.g., merge "Nam" into "Nam Tran")
  Future<void> mergeEntities(String type, String fromValue, String toValue) async {
    await _service.mergeEntities(type, fromValue, toValue);
    _syncEngine.syncNow();
    _ref.invalidate(smartListsProvider);
  }

  /// Remove an entity from all tasks
  Future<void> removeEntity(String type, String value) async {
    await _service.removeEntity(type, value);
    _syncEngine.syncNow();
    _ref.invalidate(smartListsProvider);
  }

  /// Remove a single entity from a specific task
  Future<Task> removeEntityFromTask(String taskId, String type, String value) async {
    final task = await _service.removeEntityFromTask(taskId, type, value);
    // Update local store with server response
    _store.updateTaskFromServer(task);
    // Refresh task list and smart lists
    _ref.invalidate(tasksFetchProvider);
    _ref.invalidate(smartListsProvider);
    return task;
  }

  /// Revert AI-cleaned title/description back to original
  Future<Task> aiRevert(String taskId) async {
    final task = await _service.aiRevert(taskId);
    // Update local store with server response
    _store.updateTaskFromServer(task);
    // Force refresh task list to ensure UI updates immediately
    _ref.invalidate(tasksFetchProvider);
    return task;
  }

  /// Reorder subtasks within a parent task
  Future<void> reorderSubtasks(String parentId, List<String> taskIds) async {
    await _service.reorderChildren(parentId, taskIds);
    // Refresh subtasks to get updated sort_order from server
    _ref.invalidate(subtasksProvider(parentId));
    _ref.invalidate(tasksFetchProvider);
  }

  /// Refresh a single task from the server (fetches latest data)
  Future<Task> refresh(String taskId) async {
    final task = await _service.getById(taskId);
    // Update local store with server response
    _store.updateTaskFromServer(task);
    return task;
  }
}

final taskActionsProvider = Provider<TaskActions>((ref) {
  return TaskActions(ref);
});

// Sidebar navigation (default to 1 = Next 7 days)
final selectedSidebarIndexProvider = StateProvider<int>((ref) => 1);

// Group by date toggle (default to true for all views)
final groupByDateProvider = StateProvider<bool>((ref) => true);

// Completed tasks group mode (due date or completion date)
enum CompletedGroupMode { dueDate, completionDate }
final completedGroupModeProvider = StateProvider<CompletedGroupMode>((ref) => CompletedGroupMode.dueDate);

// Show completed tasks in main views (default false)
final showCompletedTasksProvider = StateProvider<bool>((ref) => false);

// Per-view show completed state (key: "list_<id>" or "smart_<type>_<value>")
// Default is true for lists and smart lists
final showCompletedPerViewProvider = StateNotifierProvider<ShowCompletedPerViewNotifier, Map<String, bool>>((ref) {
  return ShowCompletedPerViewNotifier();
});

class ShowCompletedPerViewNotifier extends StateNotifier<Map<String, bool>> {
  ShowCompletedPerViewNotifier() : super({});

  bool isShowingCompleted(String viewKey) {
    // Default to true for lists and smart lists
    return state[viewKey] ?? true;
  }

  void toggle(String viewKey) {
    final current = isShowingCompleted(viewKey);
    state = {...state, viewKey: !current};
  }

  void set(String viewKey, bool value) {
    state = {...state, viewKey: value};
  }
}

// Lists section expanded state (collapsed by default)
final listsExpandedProvider = StateProvider<bool>((ref) => false);

// List search query
final listSearchQueryProvider = StateProvider<String>((ref) => '');

// Global task search query
final globalSearchQueryProvider = StateProvider<String>((ref) => '');

// Global task search active state
final globalSearchActiveProvider = StateProvider<bool>((ref) => false);

// Recent searches (max 10, persisted via SharedPreferences in widget)
final recentSearchesProvider = StateProvider<List<String>>((ref) => []);

/// Filtered lists based on search query
final filteredListsProvider = Provider<List<TaskList>>((ref) {
  final lists = ref.watch(listTreeProvider);
  final query = ref.watch(listSearchQueryProvider).toLowerCase().trim();

  if (query.isEmpty) return lists;

  return lists.where((list) =>
    list.name.toLowerCase().contains(query) ||
    list.fullPath.toLowerCase().contains(query)
  ).toList();
});

/// Global search results - searches across all tasks
final globalSearchResultsProvider = Provider<List<Task>>((ref) {
  final query = ref.watch(globalSearchQueryProvider).toLowerCase().trim();
  if (query.isEmpty) return [];

  final tasks = ref.watch(tasksProvider);
  return tasks.where((task) {
    final title = task.title.toLowerCase();
    final displayTitle = task.displayTitle.toLowerCase();
    final description = (task.description ?? '').toLowerCase();

    return title.contains(query) ||
           displayTitle.contains(query) ||
           description.contains(query);
  }).toList();
});

/// Get overdue tasks (root-level only)
final overdueTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final filtered = tasks
      .where((t) =>
          t.isOverdue &&
          t.status != TaskStatus.completed &&
          t.status != TaskStatus.cancelled &&
          t.parentId == null)
      .toList();
  // Sort by due date ascending (oldest first)
  filtered.sort((a, b) => (a.dueAt ?? DateTime.now()).compareTo(b.dueAt ?? DateTime.now()));
  return filtered;
});

// Selected task for detail panel
final selectedTaskIdProvider = StateProvider<String?>((ref) => null);

// Track if task detail was opened for a newly created task (shows "Done" button)
final isNewlyCreatedTaskProvider = StateProvider<bool>((ref) => false);

/// Get the selected task from the local store
final selectedTaskProvider = Provider<Task?>((ref) {
  final taskId = ref.watch(selectedTaskIdProvider);
  if (taskId == null) return null;

  final tasks = ref.watch(tasksProvider);
  return tasks.where((t) => t.id == taskId).firstOrNull;
});

/// Gets subtasks (children) for a specific task
/// Derives from tasksProvider to include locally created (optimistic) subtasks
/// Sorting: incomplete first (by sortOrder), then completed at bottom
/// (most recently completed first, earliest completed at very bottom)
final subtasksProvider = Provider.family<List<Task>, String>((ref, taskId) {
  final tasks = ref.watch(tasksProvider);
  // Filter tasks that have this task as their parent (exclude cancelled/deleted)
  final subtasks = tasks
      .where((t) => t.parentId == taskId && t.status != TaskStatus.cancelled)
      .toList();

  // Separate into incomplete and completed
  final incomplete = subtasks.where((t) => !t.isCompleted).toList();
  final completed = subtasks.where((t) => t.isCompleted).toList();

  // Sort incomplete by sortOrder (user-defined order), then by createdAt as fallback
  incomplete.sort((a, b) {
    final orderCompare = a.sortOrder.compareTo(b.sortOrder);
    if (orderCompare != 0) return orderCompare;
    return a.createdAt.compareTo(b.createdAt);
  });

  // Sort completed by completedAt descending (most recently completed first,
  // earliest completed at very bottom)
  completed.sort((a, b) {
    final aTime = a.completedAt ?? a.updatedAt;
    final bTime = b.completedAt ?? b.updatedAt;
    return bTime.compareTo(aTime); // descending
  });

  // Combine: incomplete first, then completed
  return [...incomplete, ...completed];
});

// =====================================================
// List Providers (Bear-style #List/Sublist)
// =====================================================

/// All lists (flat) - delegates to dynamic listTreeProvider
final listsProvider = Provider<List<TaskList>>((ref) {
  return ref.watch(listTreeProvider);
});

/// Regex for extracting hashtags (supports nested like #parent/child)
final _hashtagRegex = RegExp(r'#([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)?)');

/// Dynamic lists derived from task descriptions - always in sync!
/// This extracts hashtags from all tasks and builds the list dynamically.
/// Handles hierarchy: #parent/child creates both "parent" and "child" under it.
final listTreeProvider = Provider<List<TaskList>>((ref) {
  final tasks = ref.watch(tasksProvider);

  // Extract all hashtags from titles and descriptions
  // hashtagCounts: fullPath -> count of tasks with this EXACT hashtag
  final hashtagCounts = <String, int>{};

  for (final task in tasks) {
    if (task.status == TaskStatus.completed || task.status == TaskStatus.cancelled) continue;

    final text = '${task.title} ${task.description ?? ''}';
    final matches = _hashtagRegex.allMatches(text);

    for (final match in matches) {
      final hashtag = match.group(1)!; // The captured group without #
      hashtagCounts[hashtag] = (hashtagCounts[hashtag] ?? 0) + 1;
    }
  }

  // Build tree structure
  // For #parent/child, we need to:
  // 1. Ensure "parent" exists (even if no task has just #parent)
  // 2. Show "child" indented under "parent"
  final parentCounts = <String, int>{}; // parent name -> total count of children
  final childrenByParent = <String, Map<String, int>>{}; // parent -> {child: count}

  for (final entry in hashtagCounts.entries) {
    final hashtag = entry.key;
    final count = entry.value;
    final parts = hashtag.split('/');

    if (parts.length > 1) {
      // Nested: #parent/child
      final parent = parts[0];
      final child = parts[1];
      childrenByParent.putIfAbsent(parent, () => {});
      childrenByParent[parent]![child] = count;
      parentCounts[parent] = (parentCounts[parent] ?? 0) + count;
    } else {
      // Root level: #tag
      // Might also be a parent if we have #tag/subtag elsewhere
      parentCounts.putIfAbsent(hashtag, () => 0);
      parentCounts[hashtag] = parentCounts[hashtag]! + count;
    }
  }

  // Build flat list with proper ordering (parent, then its children, then next parent)
  final lists = <TaskList>[];
  final now = DateTime.now();
  final sortedParents = parentCounts.keys.toList()..sort();

  for (final parent in sortedParents) {
    final children = childrenByParent[parent];
    final hasChildren = children != null && children.isNotEmpty;

    // Add parent
    lists.add(TaskList(
      id: 'dynamic_$parent',
      name: parent,
      fullPath: parent,
      depth: 0,
      taskCount: parentCounts[parent]!,
      parentId: null,
      createdAt: now,
      updatedAt: now,
    ));

    // Add children (indented)
    if (hasChildren) {
      final sortedChildren = children.keys.toList()..sort();
      for (final child in sortedChildren) {
        lists.add(TaskList(
          id: 'dynamic_$parent/$child',
          name: child,
          fullPath: '$parent/$child',
          depth: 1,
          taskCount: children[child]!,
          parentId: 'dynamic_$parent',
          createdAt: now,
          updatedAt: now,
        ));
      }
    }
  }

  return lists;
});

/// Search lists by query (local filtering)
final listSearchProvider = Provider.family<List<TaskList>, String>((ref, query) {
  final lists = ref.watch(listsProvider);
  if (query.isEmpty) return lists;

  final queryLower = query.toLowerCase();
  return lists.where((list) {
    return list.name.toLowerCase().contains(queryLower) ||
           list.fullPath.toLowerCase().contains(queryLower);
  }).toList();
});

/// Currently selected list for viewing
final selectedListIdProvider = StateProvider<String?>((ref) => null);

/// Get tasks in selected list (local filtering by hashtag)
/// Uses per-view show completed state (default: true for lists)
final selectedListTasksProvider = Provider<List<Task>>((ref) {
  final listId = ref.watch(selectedListIdProvider);
  if (listId == null) return [];

  // Extract hashtag from list ID (format: "dynamic_hashtag")
  if (!listId.startsWith('dynamic_')) return [];
  final hashtag = listId.substring('dynamic_'.length);

  final tasks = ref.watch(tasksProvider);
  final viewKey = 'list_$listId';
  final showCompleted = ref.watch(showCompletedPerViewProvider.select((s) => s[viewKey] ?? true));
  final pattern = RegExp(r'#' + RegExp.escape(hashtag) + r'(?:\b|$)', caseSensitive: false);

  final filtered = tasks.where((task) {
    if (task.status == TaskStatus.cancelled) return false;
    if (!showCompleted && task.status == TaskStatus.completed) return false;
    final text = '${task.title} ${task.description ?? ''}';
    return pattern.hasMatch(text);
  }).toList();

  // Sort: pending tasks first, then completed (completed will be grouped separately in UI)
  filtered.sort((a, b) {
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;
    return 0;
  });

  return filtered;
});

// =====================================================
// Expanded Task Provider (for inline editing)
// =====================================================

/// Currently expanded task ID for inline editing
final expandedTaskIdProvider = StateProvider<String?>((ref) => null);

// =====================================================
// Hashtag Autocomplete Provider
// =====================================================

/// Current hashtag search query (triggered when user types #)
final hashtagQueryProvider = StateProvider<String>((ref) => '');

/// Hashtag suggestions based on current query
/// Searches both name and fullPath to include sublists (Bear-style)
final hashtagSuggestionsProvider = Provider<List<TaskList>>((ref) {
  final query = ref.watch(hashtagQueryProvider);
  final lists = ref.watch(listsProvider);

  if (query.isEmpty) {
    // Return all lists when just # is typed
    return lists;
  }

  final queryLower = query.toLowerCase();

  // Handle nested list search (e.g., "Work/")
  if (query.contains('/')) {
    final parts = query.split('/');
    final parentName = parts.first;
    final subQuery = parts.length > 1 ? parts[1].toLowerCase() : '';

    // Find parent list and its sublists
    final parent = lists.where(
      (l) => l.name.toLowerCase() == parentName.toLowerCase() && l.isRoot
    ).firstOrNull;

    if (parent != null) {
      // Filter sublists of this parent
      return lists
          .where((l) =>
              l.parentId == parent.id &&
              (subQuery.isEmpty || l.name.toLowerCase().startsWith(subQuery)))
          .toList();
    }
    return [];
  }

  // Search lists where name OR any part of fullPath matches the query (Bear-style)
  // This includes sublists like "Personal/finance" when searching "f"
  return lists.where((l) {
    // Match if list name starts with query
    if (l.name.toLowerCase().startsWith(queryLower)) return true;
    // Match if any part of the path contains a segment starting with query
    final pathParts = l.fullPath.toLowerCase().split('/');
    return pathParts.any((part) => part.startsWith(queryLower));
  }).toList();
});

// =====================================================
// Attachment Providers
// =====================================================

/// Fetches attachments for a specific task
final taskAttachmentsProvider = FutureProvider.autoDispose.family<List<Attachment>, String>((ref, taskId) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final service = ref.watch(tasksServiceProvider);
  return await service.getAttachments(taskId);
});

/// Attachment actions for a task
class AttachmentActions {
  final Ref _ref;
  final String taskId;

  AttachmentActions(this._ref, this.taskId);

  TasksService get _service => _ref.read(tasksServiceProvider);
  LocalTaskStore get _store => _ref.read(localTaskStoreProvider.notifier);
  SyncEngine get _syncEngine => _ref.read(syncEngineProvider);

  /// Ensure task is synced to server before performing attachment operations
  Future<void> _ensureTaskSynced() async {
    if (_store.currentState.hasPendingCreate(taskId)) {
      // Task hasn't been synced to server yet - wait for sync
      await _syncEngine.awaitSync();
    }
  }

  /// Add a link attachment
  Future<Attachment> addLink(String url, {String? name}) async {
    await _ensureTaskSynced();
    final attachment = await _service.createLinkAttachment(
      taskId,
      url: url,
      name: name,
    );
    // Invalidate to refetch attachments
    _ref.invalidate(taskAttachmentsProvider(taskId));
    return attachment;
  }

  /// Upload a file attachment
  Future<Attachment> uploadFile({
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
  }) async {
    await _ensureTaskSynced();
    final attachment = await _service.uploadFileAttachment(
      taskId,
      fileBytes: fileBytes,
      filename: filename,
      mimeType: mimeType,
    );
    // Invalidate to refetch attachments
    _ref.invalidate(taskAttachmentsProvider(taskId));
    return attachment;
  }

  /// Delete an attachment
  Future<void> delete(String attachmentId) async {
    await _ensureTaskSynced();
    await _service.deleteAttachment(taskId, attachmentId);
    // Invalidate to refetch attachments
    _ref.invalidate(taskAttachmentsProvider(taskId));
  }
}

/// Get attachment actions for a specific task
final attachmentActionsProvider = Provider.family<AttachmentActions, String>((ref, taskId) {
  return AttachmentActions(ref, taskId);
});

// =====================================================
// AI Actions Provider
// =====================================================

/// AI actions for tasks
class AIActions {
  final Ref _ref;

  AIActions(this._ref);

  TasksService get _service => _ref.read(tasksServiceProvider);
  LocalTaskStore get _store => _ref.read(localTaskStoreProvider.notifier);
  SyncEngine get _syncEngine => _ref.read(syncEngineProvider);

  /// Ensure task is synced to server before performing AI operations
  Future<void> _ensureTaskSynced(String taskId) async {
    if (_store.currentState.hasPendingCreate(taskId)) {
      // Task hasn't been synced to server yet - wait for sync
      await _syncEngine.awaitSync();
    }
  }

  /// AI: Decompose a task into subtasks
  Future<Task> decompose(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiDecompose(taskId);

    // Update local store with parent task and all created subtasks atomically
    final allTasks = <Task>[
      result.task as Task,
      ...result.subtasks.cast<Task>(),
    ];
    _store.updateTasksFromServer(allTasks);

    // Force refresh from server to ensure data consistency
    // Wait for the refresh to complete so UI updates before returning
    _ref.invalidate(tasksFetchProvider);
    await _ref.read(tasksFetchProvider.future);

    return result.task as Task;
  }

  /// AI: Clean up a task title and description
  Future<Task> clean(String taskId) async {
    await _ensureTaskSynced(taskId);
    final task = await _service.aiClean(taskId);
    // Update the local store with the new task data
    _store.updateTaskFromServer(task);
    // Force refresh task list to ensure UI updates immediately
    _ref.invalidate(tasksFetchProvider);
    return task;
  }

  /// AI: Clean up just the task title
  Future<Task> cleanTitle(String taskId) async {
    await _ensureTaskSynced(taskId);
    final task = await _service.aiCleanTitle(taskId);
    _store.updateTaskFromServer(task);
    // Force refresh task list to ensure UI updates immediately
    _ref.invalidate(tasksFetchProvider);
    return task;
  }

  /// AI: Clean up just the task description
  Future<Task> cleanDescription(String taskId) async {
    await _ensureTaskSynced(taskId);
    final task = await _service.aiCleanDescription(taskId);
    _store.updateTaskFromServer(task);
    // Force refresh task list to ensure UI updates immediately
    _ref.invalidate(tasksFetchProvider);
    return task;
  }

  /// AI: Extract entities from task
  Future<AIExtractResult> extract(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiExtract(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    // Refresh smart lists sidebar to show updated entity counts
    _ref.invalidate(smartListsProvider);
    // Force refresh task list to ensure UI updates immediately
    _ref.invalidate(tasksFetchProvider);
    return result;
  }

  /// AI: Check for duplicate tasks
  Future<AIDuplicatesResult> checkDuplicates(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiCheckDuplicates(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    // Force refresh task list to ensure UI updates immediately
    _ref.invalidate(tasksFetchProvider);
    return result;
  }

  /// AI: Resolve/dismiss duplicate warning
  Future<Task> resolveDuplicate(String taskId) async {
    await _ensureTaskSynced(taskId);
    final task = await _service.aiResolveDuplicate(taskId);
    _store.updateTaskFromServer(task);
    _ref.invalidate(tasksFetchProvider);
    return task;
  }

  /// AI: Rate task complexity (1-10)
  Future<AIRateResult> rate(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiRate(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    _ref.invalidate(tasksFetchProvider);
    return result;
  }

  /// AI: Suggest reminder time
  Future<AIRemindResult> remind(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiRemind(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    _ref.invalidate(tasksFetchProvider);
    return result;
  }

  /// AI: Draft an email based on task
  Future<AIDraftResult> email(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiEmail(taskId);
    return result;
  }

  /// AI: Draft a calendar invite based on task
  Future<AIDraftResult> invite(String taskId) async {
    await _ensureTaskSynced(taskId);
    final result = await _service.aiInvite(taskId);
    return result;
  }
}

final aiActionsProvider = Provider<AIActions>((ref) {
  return AIActions(ref);
});

// =====================================================
// AI Usage & Tier Providers
// =====================================================

/// Fetches AI usage stats from server
final aiUsageProvider = FutureProvider.autoDispose<AIUsageStats?>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return null;

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return null;

  try {
    final service = ref.watch(tasksServiceProvider);
    return await service.getAIUsage();
  } catch (e) {
    // AI service might not be available
    return null;
  }
});

/// Get user's subscription tier
final userTierProvider = Provider<UserTier>((ref) {
  final asyncValue = ref.watch(aiUsageProvider);
  return asyncValue.when(
    data: (stats) => stats?.tier ?? UserTier.free,
    loading: () => UserTier.free,
    error: (_, __) => UserTier.free,
  );
});

/// Check if user can use a specific AI feature
final canUseAIFeatureProvider = Provider.family<bool, AIFeature>((ref, feature) {
  final asyncValue = ref.watch(aiUsageProvider);
  return asyncValue.when(
    data: (stats) => stats?.canUse(feature) ?? false,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// Fetches AI drafts from server
final aiDraftsProvider = FutureProvider.autoDispose<List<AIDraft>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return [];

  try {
    final service = ref.watch(tasksServiceProvider);
    return await service.getAIDrafts();
  } catch (e) {
    return [];
  }
});

/// AI Draft actions
class AIDraftActions {
  final Ref _ref;

  AIDraftActions(this._ref);

  TasksService get _service => _ref.read(tasksServiceProvider);

  /// Approve a draft
  Future<void> approve(String draftId, {bool send = false}) async {
    await _service.approveDraft(draftId, send: send);
    _ref.invalidate(aiDraftsProvider);
  }

  /// Delete/cancel a draft
  Future<void> delete(String draftId) async {
    await _service.deleteDraft(draftId);
    _ref.invalidate(aiDraftsProvider);
  }
}

final aiDraftActionsProvider = Provider<AIDraftActions>((ref) {
  return AIDraftActions(ref);
});

// =====================================================
// AI Preferences Provider
// =====================================================

/// AI preferences notifier - persists settings locally
class AIPreferencesNotifier extends StateNotifier<AIPreferences> {
  Completer<void>? _loadCompleter;

  AIPreferencesNotifier() : super(AIPreferences.defaults()) {
    _loadCompleter = Completer<void>();
    _load();
  }

  /// Wait for preferences to be loaded from disk
  Future<void> ensureLoaded() async {
    await _loadCompleter?.future;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('ai_preferences');
      if (json != null) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(_decodeJson(json));
        state = AIPreferences.fromJson(data);
      }
    } catch (e) {
      // Use defaults on error
    } finally {
      _loadCompleter?.complete();
    }
  }

  Map<String, dynamic> _decodeJson(String json) {
    // Simple JSON parsing for our flat structure
    final result = <String, dynamic>{};
    // Remove braces and split by comma
    final content = json.substring(1, json.length - 1);
    if (content.isEmpty) return result;
    final pairs = content.split(',');
    for (final pair in pairs) {
      final kv = pair.split(':');
      if (kv.length == 2) {
        final key = kv[0].trim().replaceAll('"', '');
        final value = kv[1].trim().replaceAll('"', '');
        result[key] = value;
      }
    }
    return result;
  }

  String _encodeJson(Map<String, dynamic> data) {
    final pairs = data.entries.map((e) => '"${e.key}":"${e.value}"').join(',');
    return '{$pairs}';
  }

  Future<void> setSetting(AIFeature feature, AISetting setting) async {
    state = state.copyWithFeature(feature: feature, setting: setting);
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_preferences', _encodeJson(state.toJson()));
    } catch (e) {
      // Ignore save errors
    }
  }
}

final aiPreferencesProvider =
    StateNotifierProvider<AIPreferencesNotifier, AIPreferences>((ref) {
  return AIPreferencesNotifier();
});

/// Check if a feature should run automatically
final shouldAutoRunProvider = Provider.family<bool, AIFeature>((ref, feature) {
  final prefs = ref.watch(aiPreferencesProvider);
  return prefs.getSetting(feature) == AISetting.auto;
});

/// Check if a feature is enabled (always true since "off" option was removed)
final isFeatureEnabledProvider = Provider.family<bool, AIFeature>((ref, feature) {
  return true; // All AI features are now always enabled
});

// =====================================================
// Subscription Providers
// =====================================================

/// Fetches user's subscription from server
final userSubscriptionProvider = FutureProvider.autoDispose<UserSubscription>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) {
    return const UserSubscription(tier: 'free');
  }

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) {
    return const UserSubscription(tier: 'free');
  }

  try {
    final service = ref.watch(tasksServiceProvider);
    return await service.getMySubscription();
  } catch (e) {
    return const UserSubscription(tier: 'free');
  }
});

/// Fetches available subscription plans
final subscriptionPlansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) async {
  final service = ref.watch(tasksServiceProvider);
  return await service.getPlans();
});

/// Subscription actions
class SubscriptionActions {
  final Ref _ref;

  SubscriptionActions(this._ref);

  TasksService get _service => _ref.read(tasksServiceProvider);

  /// Create checkout session
  Future<CheckoutResponse> createCheckout(String planId, {String? returnUrl, bool isYearly = false}) async {
    return await _service.createCheckout(planId, returnUrl: returnUrl, isYearly: isYearly);
  }

  /// Cancel subscription
  Future<void> cancel({String? reason}) async {
    await _service.cancelSubscription(reason: reason);
    _ref.invalidate(userSubscriptionProvider);
  }
}

final subscriptionActionsProvider = Provider<SubscriptionActions>((ref) {
  return SubscriptionActions(ref);
});

// =====================================================
// Admin Providers
// =====================================================

/// Check if current user is admin
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return false;

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return false;

  try {
    final service = ref.watch(tasksServiceProvider);
    return await service.checkAdmin();
  } catch (e) {
    return false;
  }
});

/// Admin user list with filter
final adminUsersProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<AdminUser>, ({String? tier, int page})>((ref, params) async {
  final service = ref.watch(tasksServiceProvider);
  return await service.getAdminUsers(
    tier: params.tier,
    page: params.page,
  );
});

/// Admin order list with filters
final adminOrdersProvider = FutureProvider.autoDispose
    .family<PaginatedResponse<Order>, ({String? status, String? provider, String? tier, int page})>((ref, params) async {
  final service = ref.watch(tasksServiceProvider);
  return await service.getAdminOrders(
    status: params.status,
    provider: params.provider,
    tier: params.tier,
    page: params.page,
  );
});

/// Admin actions
class AdminActions {
  final Ref _ref;

  AdminActions(this._ref);

  TasksService get _service => _ref.read(tasksServiceProvider);

  /// Update user subscription
  Future<void> updateUserSubscription(String userId, {
    required String tier,
    String? planId,
    DateTime? expiresAt,
  }) async {
    await _service.updateUserSubscription(userId,
      tier: tier,
      planId: planId,
      expiresAt: expiresAt,
    );
  }
}

final adminActionsProvider = Provider<AdminActions>((ref) {
  return AdminActions(ref);
});

// =====================================================
// AI Config Providers
// =====================================================

/// Fetches AI prompt configurations (admin only)
final aiConfigsProvider = FutureProvider.autoDispose<List<AIPromptConfig>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return [];

  try {
    final service = ref.watch(tasksServiceProvider);
    return await service.getAIConfigs();
  } catch (e) {
    return [];
  }
});

/// AI config actions
class AIConfigActions {
  final Ref _ref;

  AIConfigActions(this._ref);

  TasksService get _service => _ref.read(tasksServiceProvider);

  /// Update an AI config
  Future<void> update(String key, String value) async {
    await _service.updateAIConfig(key, value);
    _ref.invalidate(aiConfigsProvider);
  }
}

final aiConfigActionsProvider = Provider<AIConfigActions>((ref) {
  return AIConfigActions(ref);
});

// =====================================================
// Smart Lists Providers (AI-extracted entities)
// =====================================================

/// Fetches aggregated entities from server for Smart Lists sidebar
final smartListsProvider = FutureProvider.autoDispose<Map<String, List<SmartListItem>>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return {};

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return {};

  try {
    final service = ref.watch(tasksServiceProvider);
    return await service.getEntities();
  } catch (e) {
    return {};
  }
});

/// Selected smart list entity (type + value)
final selectedSmartListProvider = StateProvider<({String type, String value})?>((ref) => null);

/// Tasks filtered by selected smart list entity
/// Uses per-view show completed state (default: true for smart lists)
final smartListTasksProvider = Provider<List<Task>>((ref) {
  final selection = ref.watch(selectedSmartListProvider);
  if (selection == null) return [];

  final tasks = ref.watch(tasksProvider);
  final viewKey = 'smart_${selection.type}_${selection.value}';
  final showCompleted = ref.watch(showCompletedPerViewProvider.select((s) => s[viewKey] ?? true));
  final searchValue = selection.value.toLowerCase();

  // Extract significant words from entity value for fuzzy matching
  // (excluding common suffixes like "city", "office", "company", etc.)
  final commonSuffixes = {'city', 'office', 'company', 'inc', 'corp', 'ltd', 'llc'};
  final entityWords = searchValue
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2 && !commonSuffixes.contains(w))
      .toList();

  final filtered = tasks.where((task) {
    // Skip subtasks - only show main tasks in smart lists
    if (task.parentId != null) return false;
    // Skip cancelled tasks always
    if (task.status == TaskStatus.cancelled) return false;
    // Skip completed tasks unless showCompleted is true
    if (!showCompleted && task.status == TaskStatus.completed) return false;

    // Check if task has matching entity in extracted entities
    final hasMatchingEntity = task.entities.any((e) =>
        e.type == selection.type &&
        e.value.toLowerCase() == searchValue);

    if (hasMatchingEntity) return true;

    // Fallback: Search title and description for entity words
    // This handles cases where extraction hasn't synced yet or entity value
    // is slightly different from raw text (e.g., "Hochiminh city" vs "Hochiminh")
    final titleLower = task.title.toLowerCase();
    final descLower = task.description?.toLowerCase() ?? '';
    final combinedText = '$titleLower $descLower';

    // Check if any significant word from entity is in the task text
    final hasTextMatch = entityWords.any((word) => combinedText.contains(word));

    return hasTextMatch;
  }).toList();

  // Sort: pending tasks first, then completed (completed will be grouped separately in UI)
  filtered.sort((a, b) {
    if (a.isCompleted && !b.isCompleted) return 1;
    if (!a.isCompleted && b.isCompleted) return -1;
    return 0;
  });

  return filtered;
});

/// Smart Lists section expanded state (collapsed by default)
final smartListsExpandedProvider = StateProvider<bool>((ref) => false);
