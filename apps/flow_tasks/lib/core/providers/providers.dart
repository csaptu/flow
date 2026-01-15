import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    }
  }

  Future<void> logout() async {
    final authService = _ref.read(authServiceProvider);
    await authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// Tasks providers
final tasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final service = ref.watch(tasksServiceProvider);
  final response = await service.list();
  return response.items;
});

final todayTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final service = ref.watch(tasksServiceProvider);
  return service.getToday();
});

final inboxTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final service = ref.watch(tasksServiceProvider);
  return service.getInbox();
});

final upcomingTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  final service = ref.watch(tasksServiceProvider);
  return service.getUpcoming();
});

// Sidebar navigation
final selectedSidebarIndexProvider = StateProvider<int>((ref) => 0);
