import 'package:dio/dio.dart';
import 'package:flow_models/flow_models.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'tasks_service.dart';

/// Projects service
class ProjectsService {
  final FlowApiClient _client;

  ProjectsService(this._client);

  Dio get _dio => _client.projectsClient;

  /// Create a new project
  Future<Project> create({
    required String name,
    String? description,
    String? methodology,
    String? color,
    String? icon,
    DateTime? startDate,
    DateTime? targetDate,
  }) async {
    final response = await _dio.post('/projects', data: {
      'name': name,
      'description': description,
      'methodology': methodology,
      'color': color,
      'icon': icon,
      'start_date': startDate?.toIso8601String(),
      'target_date': targetDate?.toIso8601String(),
    });

    if (response.data['success'] == true) {
      return Project.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// List projects
  Future<PaginatedResponse<Project>> list({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get('/projects', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });

    if (response.data['success'] == true) {
      final projects = (response.data['data'] as List)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = response.data['meta'] != null
          ? ApiMeta.fromJson(response.data['meta'])
          : null;
      return PaginatedResponse(items: projects, meta: meta);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get project by ID
  Future<Project> getById(String id) async {
    final response = await _dio.get('/projects/$id');

    if (response.data['success'] == true) {
      return Project.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update a project
  Future<Project> update(String id, {
    String? name,
    String? description,
    String? status,
    String? methodology,
    String? color,
    String? icon,
    DateTime? startDate,
    DateTime? targetDate,
  }) async {
    final response = await _dio.put('/projects/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (methodology != null) 'methodology': methodology,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (targetDate != null) 'target_date': targetDate.toIso8601String(),
    });

    if (response.data['success'] == true) {
      return Project.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Delete a project
  Future<void> delete(String id) async {
    await _dio.delete('/projects/$id');
  }

  /// List project members
  Future<List<ProjectMember>> listMembers(String projectId) async {
    final response = await _dio.get('/projects/$projectId/members');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => ProjectMember.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Add project member
  Future<void> addMember(String projectId, String userId, String role) async {
    await _dio.post('/projects/$projectId/members', data: {
      'user_id': userId,
      'role': role,
    });
  }

  /// Remove project member
  Future<void> removeMember(String projectId, String memberId) async {
    await _dio.delete('/projects/$projectId/members/$memberId');
  }

  // WBS operations

  /// Create WBS node
  Future<WBSNode> createWBSNode(String projectId, {
    required String title,
    String? description,
    String? parentId,
    String? assigneeId,
    int? priority,
    DateTime? plannedStart,
    DateTime? plannedEnd,
  }) async {
    final response = await _dio.post('/projects/$projectId/wbs', data: {
      'title': title,
      'description': description,
      'parent_id': parentId,
      'assignee_id': assigneeId,
      'priority': priority,
      'planned_start': plannedStart?.toIso8601String(),
      'planned_end': plannedEnd?.toIso8601String(),
    });

    if (response.data['success'] == true) {
      return WBSNode.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// List WBS nodes
  Future<List<WBSNode>> listWBSNodes(String projectId) async {
    final response = await _dio.get('/projects/$projectId/wbs');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => WBSNode.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get WBS tree structure
  Future<List<dynamic>> getWBSTree(String projectId) async {
    final response = await _dio.get('/projects/$projectId/wbs/tree');

    if (response.data['success'] == true) {
      return response.data['data'] as List;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update WBS node
  Future<WBSNode> updateWBSNode(String projectId, String nodeId, {
    String? title,
    String? description,
    String? status,
    int? priority,
    String? assigneeId,
    DateTime? plannedStart,
    DateTime? plannedEnd,
  }) async {
    final response = await _dio.put('/projects/$projectId/wbs/$nodeId', data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (plannedStart != null) 'planned_start': plannedStart.toIso8601String(),
      if (plannedEnd != null) 'planned_end': plannedEnd.toIso8601String(),
    });

    if (response.data['success'] == true) {
      return WBSNode.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update WBS node progress
  Future<WBSNode> updateWBSProgress(
    String projectId,
    String nodeId,
    double progress,
  ) async {
    final response = await _dio.put(
      '/projects/$projectId/wbs/$nodeId/progress',
      data: {'progress': progress},
    );

    if (response.data['success'] == true) {
      return WBSNode.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Delete WBS node
  Future<void> deleteWBSNode(String projectId, String nodeId) async {
    await _dio.delete('/projects/$projectId/wbs/$nodeId');
  }

  // Dependencies

  /// Add dependency
  Future<void> addDependency(String projectId, {
    required String predecessorId,
    required String successorId,
    String dependencyType = 'FS',
    int lagDays = 0,
  }) async {
    await _dio.post('/projects/$projectId/dependencies', data: {
      'predecessor_id': predecessorId,
      'successor_id': successorId,
      'dependency_type': dependencyType,
      'lag_days': lagDays,
    });
  }

  /// List dependencies
  Future<List<WBSDependency>> listDependencies(String projectId) async {
    final response = await _dio.get('/projects/$projectId/dependencies');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => WBSDependency.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Remove dependency
  Future<void> removeDependency(String projectId, String depId) async {
    await _dio.delete('/projects/$projectId/dependencies/$depId');
  }

  /// Get Gantt chart data
  Future<List<GanttBar>> getGantt(String projectId) async {
    final response = await _dio.get('/projects/$projectId/gantt');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => GanttBar.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get tasks assigned to current user (for Tasks app integration)
  Future<List<WBSNode>> getAssignedToMe() async {
    final response = await _dio.get('/assigned-to-me');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => WBSNode.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }
}
