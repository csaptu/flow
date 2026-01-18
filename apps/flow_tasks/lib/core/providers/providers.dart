import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  // Use development config for now
  return FlowApiClient(config: ApiConfig.development());
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

  Future<void> register(String email, String password, String name) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final authService = _ref.read(authServiceProvider);
      final response = await authService.register(
        email: email,
        password: password,
        name: name,
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
        // Use google_sign_in package on mobile
        final googleSignIn = GoogleSignIn(
          scopes: ['email', 'profile'],
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
}

// Tasks providers - use optimistic local store with server fetch

/// Fetches tasks from server and updates local store
final _tasksFetchProvider = FutureProvider.autoDispose<void>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return;

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return;

  final service = ref.watch(tasksServiceProvider);
  final localStore = ref.watch(localTaskStoreProvider.notifier);

  // Fetch and store
  final response = await service.list();
  localStore.setServerTasks(response.items);
});

/// All tasks (merged optimistic + server)
final tasksProvider = Provider<List<Task>>((ref) {
  // Trigger server fetch
  ref.watch(_tasksFetchProvider);

  // Watch state to rebuild when it changes
  ref.watch(localTaskStoreProvider);
  final localStore = ref.read(localTaskStoreProvider.notifier);

  // Get merged tasks (server + optimistic - deleted)
  return localStore.getMergedTasks();
});

/// All tasks (non-completed, sorted by createdAt descending)
final allTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final filtered = tasks
      .where((t) => t.status != TaskStatus.completed && t.status != TaskStatus.cancelled)
      .toList();
  // Sort by createdAt descending (latest first)
  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return filtered;
});

/// Legacy inbox provider for backward compatibility
final inboxTasksProvider = Provider<List<Task>>((ref) {
  return ref.watch(allTasksProvider);
});

/// Today's tasks (includes overdue)
final todayTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  final filtered = tasks.where((t) {
    if (t.dueDate == null || t.status == TaskStatus.completed) return false;
    final dueDate = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
    // Include overdue (before today) OR due today
    return dueDate.isBefore(tomorrow);
  }).toList();
  // Sort by due date ascending (overdue first, then today)
  filtered.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  return filtered;
});

/// Next 7 days tasks (includes overdue + next 7 days)
final next7DaysTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final in7Days = today.add(const Duration(days: 7));

  final filtered = tasks.where((t) {
    if (t.dueDate == null || t.status == TaskStatus.completed || t.status == TaskStatus.cancelled) return false;
    final dueDate = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
    // Include overdue (before today) OR within next 7 days
    return dueDate.isBefore(in7Days);
  }).toList();
  // Sort by due date ascending (overdue first)
  filtered.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  return filtered;
});

/// Legacy upcoming provider for backward compatibility
final upcomingTasksProvider = Provider<List<Task>>((ref) {
  return ref.watch(next7DaysTasksProvider);
});

/// Completed tasks
final completedTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  return tasks.where((t) => t.status == TaskStatus.completed).toList();
});

/// Trash tasks (cancelled)
final trashTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final filtered = tasks.where((t) => t.status == TaskStatus.cancelled).toList();
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

  /// Create a task (instant, syncs in background)
  Future<Task> create({
    required String title,
    String? description,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
  }) async {
    final task = await _store.createTask(
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority,
      tags: tags,
    );

    // Trigger background sync
    _syncEngine.syncNow();

    // If task contains hashtags, refresh lists after sync completes
    // The backend auto-creates lists from hashtags
    if (title.contains('#')) {
      // Refresh lists immediately and after a short delay to catch backend processing
      _ref.invalidate(_listsFetchProvider);
      _ref.invalidate(_listTreeFetchProvider);
      Future.delayed(const Duration(milliseconds: 800), () {
        _ref.invalidate(_listsFetchProvider);
        _ref.invalidate(_listTreeFetchProvider);
      });
    }

    return task;
  }

  /// Update a task (instant, syncs in background)
  Future<Task> update(
    String taskId, {
    String? title,
    String? description,
    DateTime? dueDate,
    int? priority,
    String? status,
    List<String>? tags,
    bool? skipAutoCleanup,
  }) async {
    final task = await _store.updateTask(
      taskId,
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority,
      status: status,
      tags: tags,
      skipAutoCleanup: skipAutoCleanup,
    );

    _syncEngine.syncNow();

    // If title or description contains hashtags, refresh lists after sync
    final hasHashtags = (title?.contains('#') ?? false) ||
        (description?.contains('#') ?? false);
    if (hasHashtags) {
      // Refresh lists immediately and after a short delay to catch backend processing
      _ref.invalidate(_listsFetchProvider);
      _ref.invalidate(_listTreeFetchProvider);
      Future.delayed(const Duration(milliseconds: 800), () {
        _ref.invalidate(_listsFetchProvider);
        _ref.invalidate(_listTreeFetchProvider);
      });
    }

    return task;
  }

  /// Complete a task (instant)
  Future<Task> complete(String taskId) async {
    final task = await _store.completeTask(taskId);
    _syncEngine.syncNow();
    return task;
  }

  /// Uncomplete a task (instant)
  Future<Task> uncomplete(String taskId) async {
    final task = await _store.uncompleteTask(taskId);
    _syncEngine.syncNow();
    return task;
  }

  /// Delete a task (instant)
  Future<void> delete(String taskId) async {
    await _store.deleteTask(taskId);
    _syncEngine.syncNow();
  }
}

final taskActionsProvider = Provider<TaskActions>((ref) {
  return TaskActions(ref);
});

// Sidebar navigation (default to 1 = Next 7 days)
final selectedSidebarIndexProvider = StateProvider<int>((ref) => 1);

// Group by date toggle (default to true for all views)
final groupByDateProvider = StateProvider<bool>((ref) => true);

/// Get overdue tasks
final overdueTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final filtered = tasks
      .where((t) => t.isOverdue && t.status != TaskStatus.completed && t.status != TaskStatus.cancelled)
      .toList();
  // Sort by due date ascending (oldest first)
  filtered.sort((a, b) => (a.dueDate ?? DateTime.now()).compareTo(b.dueDate ?? DateTime.now()));
  return filtered;
});

// Selected task for detail panel
final selectedTaskIdProvider = StateProvider<String?>((ref) => null);

/// Get the selected task from the local store
final selectedTaskProvider = Provider<Task?>((ref) {
  final taskId = ref.watch(selectedTaskIdProvider);
  if (taskId == null) return null;

  final tasks = ref.watch(tasksProvider);
  return tasks.where((t) => t.id == taskId).firstOrNull;
});

// =====================================================
// List Providers (Bear-style #List/Sublist)
// =====================================================

/// Fetches lists from server
final _listsFetchProvider = FutureProvider.autoDispose<List<TaskList>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return [];

  final service = ref.watch(tasksServiceProvider);
  return await service.getLists();
});

/// All lists (flat)
final listsProvider = Provider<List<TaskList>>((ref) {
  final asyncValue = ref.watch(_listsFetchProvider);
  return asyncValue.when(
    data: (lists) => lists,
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Fetches list tree from server (active lists)
final _listTreeFetchProvider = FutureProvider.autoDispose<List<TaskList>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return [];

  final service = ref.watch(tasksServiceProvider);
  return await service.getListTree(archived: false);
});

/// Lists as hierarchical tree (active only)
final listTreeProvider = Provider<List<TaskList>>((ref) {
  final asyncValue = ref.watch(_listTreeFetchProvider);
  return asyncValue.when(
    data: (lists) => lists,
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Fetches archived list tree from server
final _archivedListTreeFetchProvider = FutureProvider.autoDispose<List<TaskList>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final client = ref.watch(apiClientProvider);
  if (!client.isAuthenticated) return [];

  final service = ref.watch(tasksServiceProvider);
  return await service.getListTree(archived: true);
});

/// Archived lists as hierarchical tree
final archivedListTreeProvider = Provider<List<TaskList>>((ref) {
  final asyncValue = ref.watch(_archivedListTreeFetchProvider);
  return asyncValue.when(
    data: (lists) => lists,
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Search lists by query
final listSearchProvider = FutureProvider.autoDispose.family<List<TaskList>, String>((ref, query) async {
  if (query.isEmpty) {
    return ref.watch(listsProvider);
  }

  final authState = ref.watch(authStateProvider);
  if (authState.status != AuthStatus.authenticated) return [];

  final service = ref.watch(tasksServiceProvider);
  return await service.searchLists(query);
});

/// Currently selected list for viewing
final selectedListIdProvider = StateProvider<String?>((ref) => null);

/// Get tasks in selected list
final selectedListTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final listId = ref.watch(selectedListIdProvider);
  if (listId == null) return [];

  final service = ref.watch(tasksServiceProvider);
  return await service.getListTasks(listId, includeSublists: true);
});

// =====================================================
// List Actions (CRUD + Cleanup)
// =====================================================

/// List actions for creating, deleting, archiving, and cleaning up lists
class ListActions {
  final Ref _ref;

  ListActions(this._ref);

  TasksService get _service => _ref.read(tasksServiceProvider);

  /// Create a new list
  Future<TaskList> create({
    required String name,
    String? icon,
    String? color,
    String? parentId,
  }) async {
    final list = await _service.createList(
      name: name,
      icon: icon,
      color: color,
      parentId: parentId,
    );

    // Trigger cleanup after creating a list
    cleanupEmptyLists();

    // Refresh list providers
    _refreshListProviders();

    return list;
  }

  /// Delete a list
  Future<void> delete(String listId) async {
    await _service.deleteList(listId);
    _refreshListProviders();
  }

  /// Archive a list (move to archived lists)
  Future<void> archive(String listId) async {
    await _service.archiveList(listId);
    _refreshListProviders();
  }

  /// Unarchive a list (restore from archived lists)
  Future<void> unarchive(String listId) async {
    await _service.unarchiveList(listId);
    _refreshListProviders();
  }

  /// Cleanup empty lists (runs automatically)
  Future<int> cleanupEmptyLists() async {
    try {
      final result = await _service.cleanupEmptyLists();
      final totalDeleted = result['total_deleted'] as int? ?? 0;

      if (totalDeleted > 0) {
        _refreshListProviders();
      }

      return totalDeleted;
    } catch (e) {
      // Silently fail - cleanup is a background operation
      return 0;
    }
  }

  void _refreshListProviders() {
    _ref.invalidate(_listsFetchProvider);
    _ref.invalidate(_listTreeFetchProvider);
    _ref.invalidate(_archivedListTreeFetchProvider);
  }
}

final listActionsProvider = Provider<ListActions>((ref) {
  return ListActions(ref);
});

/// Cleanup service state
class ListCleanupState {
  final bool isRunning;
  final DateTime? lastRun;
  final int? lastDeletedCount;

  const ListCleanupState({
    this.isRunning = false,
    this.lastRun,
    this.lastDeletedCount,
  });

  ListCleanupState copyWith({
    bool? isRunning,
    DateTime? lastRun,
    int? lastDeletedCount,
  }) {
    return ListCleanupState(
      isRunning: isRunning ?? this.isRunning,
      lastRun: lastRun ?? this.lastRun,
      lastDeletedCount: lastDeletedCount ?? this.lastDeletedCount,
    );
  }
}

/// Cleanup service notifier for periodic cleanup
class ListCleanupNotifier extends StateNotifier<ListCleanupState> {
  final Ref _ref;

  ListCleanupNotifier(this._ref) : super(const ListCleanupState());

  /// Run cleanup now
  Future<int> runCleanup() async {
    if (state.isRunning) return 0;

    state = state.copyWith(isRunning: true);

    try {
      final listActions = _ref.read(listActionsProvider);
      final deleted = await listActions.cleanupEmptyLists();

      state = state.copyWith(
        isRunning: false,
        lastRun: DateTime.now(),
        lastDeletedCount: deleted,
      );

      return deleted;
    } catch (e) {
      state = state.copyWith(isRunning: false);
      return 0;
    }
  }
}

final listCleanupProvider = StateNotifierProvider<ListCleanupNotifier, ListCleanupState>((ref) {
  return ListCleanupNotifier(ref);
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
final hashtagSuggestionsProvider = Provider<List<TaskList>>((ref) {
  final query = ref.watch(hashtagQueryProvider);
  final lists = ref.watch(listsProvider);

  if (query.isEmpty) {
    // Return all lists when just # is typed
    return lists;
  }

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

  // Simple prefix search
  return lists
      .where((l) => l.name.toLowerCase().startsWith(query.toLowerCase()))
      .toList();
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

  /// Add a link attachment
  Future<Attachment> addLink(String url, {String? name}) async {
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

  /// AI: Decompose a task into steps
  Future<Task> decompose(String taskId) async {
    final task = await _service.aiDecompose(taskId);
    // Update the local store with the new task data
    _store.updateTaskFromServer(task);
    return task;
  }

  /// AI: Clean up a task title and description
  Future<Task> clean(String taskId) async {
    final task = await _service.aiClean(taskId);
    // Update the local store with the new task data
    _store.updateTaskFromServer(task);
    return task;
  }

  /// AI: Clean up just the task title
  Future<Task> cleanTitle(String taskId) async {
    // Currently uses same endpoint - backend stores original before cleaning
    final task = await _service.aiClean(taskId);
    _store.updateTaskFromServer(task);
    return task;
  }

  /// AI: Clean up just the task description
  Future<Task> cleanDescription(String taskId) async {
    // Currently uses same endpoint - backend stores original before cleaning
    final task = await _service.aiClean(taskId);
    _store.updateTaskFromServer(task);
    return task;
  }

  /// AI: Rate task complexity (1-10)
  Future<AIRateResult> rate(String taskId) async {
    final result = await _service.aiRate(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    return result;
  }

  /// AI: Extract entities from task
  Future<AIExtractResult> extract(String taskId) async {
    final result = await _service.aiExtract(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    return result;
  }

  /// AI: Suggest reminder time for task
  Future<AIRemindResult> remind(String taskId) async {
    final result = await _service.aiRemind(taskId);
    if (result.task is Task) {
      _store.updateTaskFromServer(result.task as Task);
    }
    return result;
  }

  /// AI: Draft email based on task
  Future<AIDraftResult> email(String taskId) async {
    return await _service.aiEmail(taskId);
  }

  /// AI: Draft calendar invite based on task
  Future<AIDraftResult> invite(String taskId) async {
    return await _service.aiInvite(taskId);
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
  AIPreferencesNotifier() : super(AIPreferences.defaults()) {
    _load();
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

/// Check if a feature is enabled (not off)
final isFeatureEnabledProvider = Provider.family<bool, AIFeature>((ref, feature) {
  final prefs = ref.watch(aiPreferencesProvider);
  return prefs.getSetting(feature) != AISetting.off;
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
  Future<CheckoutResponse> createCheckout(String planId, {String? returnUrl}) async {
    return await _service.createCheckout(planId, returnUrl: returnUrl);
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
