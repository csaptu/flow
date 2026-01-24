import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_tasks/core/router/app_router.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/core/providers/providers.dart';

/// Custom scroll behavior for smoother scrolling on web
class SmoothScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Use bouncing physics for smoother feel on all platforms
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize providers
  final container = ProviderContainer();
  await container.read(initializationProvider.future);

  // Initialize local task store (loads offline queue)
  await container.read(localTaskStoreProvider.notifier).init();

  // Check auth state before rendering to avoid unauthorized API calls
  await container.read(authStateProvider.notifier).checkAuth();

  // Start sync engine
  container.read(syncEngineProvider).start();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FlowTasksApp(),
    ),
  );
}

class FlowTasksApp extends ConsumerWidget {
  const FlowTasksApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return SelectionArea(
      child: MaterialApp.router(
        title: 'Flow Tasks',
        debugShowCheckedModeBanner: false,
        theme: FlowTheme.light(),
        darkTheme: FlowTheme.dark(),
        themeMode: themeMode,
        routerConfig: router,
        // Use smooth scrolling on web for better mobile experience
        scrollBehavior: kIsWeb ? SmoothScrollBehavior() : null,
      ),
    );
  }
}
