import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/features/auth/presentation/login_screen.dart';
import 'package:flow_tasks/features/tasks/presentation/home_screen.dart';

// Notifier to trigger router refresh without recreating the router
class AuthChangeNotifier extends ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;

  void updateStatus(AuthStatus status) {
    if (_status != status) {
      _status = status;
      notifyListeners();
    }
  }
}

final _authChangeNotifier = AuthChangeNotifier();

final routerProvider = Provider<GoRouter>((ref) {
  // Listen to auth state changes and update the notifier
  ref.listen(authStateProvider, (previous, next) {
    _authChangeNotifier.updateStatus(next.status);
  });

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _authChangeNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isAuth = authState.status == AuthStatus.authenticated;
      final isLoggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      // If not authenticated and not on login/register, redirect to login
      if (!isAuth &&
          authState.status != AuthStatus.initial &&
          authState.status != AuthStatus.loading &&
          !isLoggingIn) {
        return '/login';
      }

      // If authenticated and on login/register, redirect to home
      if (isAuth && isLoggingIn) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const LoginScreen(isRegister: true),
      ),
    ],
  );
});
