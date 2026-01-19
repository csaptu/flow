import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_api/flow_api.dart';
import 'package:flow_models/flow_models.dart';

// ============================================================================
// API Client
// ============================================================================

final apiClientProvider = Provider<FlowApiClient>((ref) {
  final baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  return FlowApiClient(
    config: ApiConfig(
      sharedServiceUrl: '$baseUrl/api/v1',
      tasksServiceUrl: '$baseUrl/api/v1',
      projectsServiceUrl: '$baseUrl/api/v1',
    ),
  );
});

// ============================================================================
// Services
// ============================================================================

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(apiClientProvider));
});

final projectsServiceProvider = Provider<ProjectsService>((ref) {
  return ProjectsService(ref.read(apiClientProvider));
});

// ============================================================================
// Auth State
// ============================================================================

enum AuthStatus { initial, authenticated, unauthenticated }

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

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final FlowApiClient _apiClient;

  AuthNotifier(this._authService, this._apiClient) : super(const AuthState());

  Future<void> checkAuth() async {
    try {
      await _apiClient.init();
      if (!_apiClient.isAuthenticated) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      final user = await _authService.getCurrentUser();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (e) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final response = await _authService.login(email: email, password: password);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: response.user,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> register(String email, String password, String name) async {
    try {
      final response = await _authService.register(email: email, password: password, name: name);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: response.user,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(authServiceProvider),
    ref.read(apiClientProvider),
  );
});

// ============================================================================
// Projects State
// ============================================================================

/// Provider for all user projects
final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final service = ref.read(projectsServiceProvider);
  final response = await service.list();
  return response.items;
});

/// Provider for active projects only
final activeProjectsProvider = FutureProvider<List<Project>>((ref) async {
  final projects = await ref.watch(projectsProvider.future);
  return projects.where((p) =>
    p.status != ProjectStatus.completed &&
    p.status != ProjectStatus.cancelled
  ).toList();
});

/// Provider for archived/completed projects
final archivedProjectsProvider = FutureProvider<List<Project>>((ref) async {
  final projects = await ref.watch(projectsProvider.future);
  return projects.where((p) =>
    p.status == ProjectStatus.completed ||
    p.status == ProjectStatus.cancelled
  ).toList();
});

/// Current selected project ID
final selectedProjectIdProvider = StateProvider<String?>((ref) => null);

/// Current selected project
final selectedProjectProvider = FutureProvider<Project?>((ref) async {
  final projectId = ref.watch(selectedProjectIdProvider);
  if (projectId == null) return null;

  final service = ref.read(projectsServiceProvider);
  return service.getById(projectId);
});

// ============================================================================
// WBS State
// ============================================================================

/// Provider for WBS nodes of selected project
final wbsNodesProvider = FutureProvider<List<WBSNode>>((ref) async {
  final projectId = ref.watch(selectedProjectIdProvider);
  if (projectId == null) return [];

  final service = ref.read(projectsServiceProvider);
  return service.listWBSNodes(projectId);
});

/// Provider for WBS tree structure
final wbsTreeProvider = FutureProvider<List<WBSTreeNode>>((ref) async {
  final nodes = await ref.watch(wbsNodesProvider.future);
  return _buildWBSTree(nodes);
});

/// Build tree structure from flat WBS nodes list
List<WBSTreeNode> _buildWBSTree(List<WBSNode> nodes) {
  final Map<String, WBSTreeNode> nodeMap = {};
  final List<WBSTreeNode> roots = [];

  // First pass: create WBSTreeNode for each node
  for (final node in nodes) {
    nodeMap[node.id] = WBSTreeNode(node: node);
  }

  // Second pass: build parent-child relationships
  for (final node in nodes) {
    final treeNode = nodeMap[node.id]!;
    if (node.parentId == null) {
      roots.add(treeNode);
    } else {
      final parent = nodeMap[node.parentId];
      if (parent != null) {
        parent.children.add(treeNode);
      } else {
        // Parent not found, treat as root
        roots.add(treeNode);
      }
    }
  }

  // Sort roots and children by position
  roots.sort((a, b) => a.node.position.compareTo(b.node.position));
  for (final node in nodeMap.values) {
    node.children.sort((a, b) => a.node.position.compareTo(b.node.position));
  }

  return roots;
}

/// WBS tree node wrapper
class WBSTreeNode {
  final WBSNode node;
  final List<WBSTreeNode> children = [];

  WBSTreeNode({required this.node});

  bool get hasChildren => children.isNotEmpty;
  int get depth => _calculateDepth(this, 0);

  static int _calculateDepth(WBSTreeNode node, int currentDepth) {
    if (node.children.isEmpty) return currentDepth;
    int maxDepth = currentDepth;
    for (final child in node.children) {
      final childDepth = _calculateDepth(child, currentDepth + 1);
      if (childDepth > maxDepth) maxDepth = childDepth;
    }
    return maxDepth;
  }
}

// ============================================================================
// UI State
// ============================================================================

/// Selected sidebar index
final selectedSidebarIndexProvider = StateProvider<int>((ref) => 0);

/// WBS view mode: tree or flat
enum WBSViewMode { tree, flat, gantt }
final wbsViewModeProvider = StateProvider<WBSViewMode>((ref) => WBSViewMode.tree);

/// Expanded WBS nodes (for tree view)
final expandedWBSNodesProvider = StateProvider<Set<String>>((ref) => {});
