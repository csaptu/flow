import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/features/auth/presentation/login_screen.dart';
import 'package:flow_tasks/features/tasks/presentation/home_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
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
