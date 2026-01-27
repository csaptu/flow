import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/features/auth/presentation/login_screen.dart';
import 'package:flow_tasks/features/auth/presentation/forgot_password_screen.dart';
import 'package:flow_tasks/features/tasks/presentation/home_screen.dart';
import 'package:flow_tasks/features/legal/presentation/pricing_screen.dart';
import 'package:flow_tasks/features/legal/presentation/terms_screen.dart';
import 'package:flow_tasks/features/legal/presentation/privacy_screen.dart';

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
      final isPublicPage = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/pricing' ||
          state.matchedLocation == '/terms' ||
          state.matchedLocation == '/privacy';

      // If not authenticated and not on public page, redirect to login
      if (!isAuth &&
          authState.status != AuthStatus.initial &&
          authState.status != AuthStatus.loading &&
          !isPublicPage) {
        return '/login';
      }

      // If authenticated and on login/register (but not legal pages), redirect to home
      final isLoginPage = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (isAuth && isLoginPage) {
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
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/pricing',
        builder: (context, state) => const PricingScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyScreen(),
      ),
    ],
  );
});
