import 'package:dio/dio.dart';
import 'package:flow_models/flow_models.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Tasks service
class TasksService {
  final FlowApiClient _client;

  TasksService(this._client);

  Dio get _dio => _client.tasksClient;

  /// Create a new task
  Future<Task> create({
    required String title,
    String? description,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
    String? parentId,
  }) async {
    final response = await _dio.post('/tasks', data: {
      'title': title,
      'description': description,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority,
      'tags': tags,
      'parent_id': parentId,
    });

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// List tasks with pagination
  Future<PaginatedResponse<Task>> list({int page = 1, int pageSize = 20}) async {
    final response = await _dio.get('/tasks', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });

    if (response.data['success'] == true) {
      final tasks = (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = response.data['meta'] != null
          ? ApiMeta.fromJson(response.data['meta'])
          : null;
      return PaginatedResponse(items: tasks, meta: meta);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get today's tasks
  Future<List<Task>> getToday() async {
    final response = await _dio.get('/tasks/today');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get inbox tasks (no due date)
  Future<List<Task>> getInbox() async {
    final response = await _dio.get('/tasks/inbox');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get upcoming tasks
  Future<List<Task>> getUpcoming() async {
    final response = await _dio.get('/tasks/upcoming');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get completed tasks
  Future<PaginatedResponse<Task>> getCompleted({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get('/tasks/completed', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });

    if (response.data['success'] == true) {
      final tasks = (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = response.data['meta'] != null
          ? ApiMeta.fromJson(response.data['meta'])
          : null;
      return PaginatedResponse(items: tasks, meta: meta);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get task by ID
  Future<Task> getById(String id) async {
    final response = await _dio.get('/tasks/$id');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update a task
  Future<Task> update(String id, {
    String? title,
    String? description,
    DateTime? dueDate,
    int? priority,
    String? status,
    List<String>? tags,
    String? groupId,
  }) async {
    final response = await _dio.put('/tasks/$id', data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (tags != null) 'tags': tags,
      if (groupId != null) 'group_id': groupId,
    });

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Delete a task
  Future<void> delete(String id) async {
    final response = await _dio.delete('/tasks/$id');

    if (response.data['success'] != true && response.statusCode != 204) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Complete a task
  Future<Task> complete(String id) async {
    final response = await _dio.post('/tasks/$id/complete');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Uncomplete a task
  Future<Task> uncomplete(String id) async {
    final response = await _dio.post('/tasks/$id/uncomplete');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Create a child task
  Future<Task> createChild(String parentId, {
    required String title,
    String? description,
    int? priority,
  }) async {
    final response = await _dio.post('/tasks/$parentId/children', data: {
      'title': title,
      'description': description,
      'priority': priority,
    });

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get children of a task
  Future<List<Task>> getChildren(String parentId) async {
    final response = await _dio.get('/tasks/$parentId/children');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Decompose task into steps
  Future<Task> aiDecompose(String id) async {
    final response = await _dio.post('/tasks/$id/ai/decompose');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Clean task title and description
  Future<Task> aiClean(String id) async {
    final response = await _dio.post('/tasks/$id/ai/clean');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// List task groups
  Future<List<TaskGroup>> listGroups() async {
    final response = await _dio.get('/groups');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => TaskGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Create a task group
  Future<TaskGroup> createGroup({
    required String name,
    String? icon,
    String? color,
  }) async {
    final response = await _dio.post('/groups', data: {
      'name': name,
      'icon': icon,
      'color': color,
    });

    if (response.data['success'] == true) {
      return TaskGroup.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }
}

/// Paginated response
class PaginatedResponse<T> {
  final List<T> items;
  final ApiMeta? meta;

  const PaginatedResponse({
    required this.items,
    this.meta,
  });

  bool get hasMore =>
      meta != null && meta!.page < meta!.totalPages;
}
