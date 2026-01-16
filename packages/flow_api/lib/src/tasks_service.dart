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

  // =====================================================
  // List Endpoints (Bear-style #List/Sublist)
  // =====================================================

  /// Get all lists (flat)
  Future<List<TaskList>> getLists({bool archived = false}) async {
    final response = await _dio.get('/lists', queryParameters: {
      'archived': archived.toString(),
    });

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => TaskList.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get lists as a tree structure
  Future<List<TaskList>> getListTree({bool archived = false}) async {
    final response = await _dio.get('/lists/tree', queryParameters: {
      'archived': archived.toString(),
    });

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => TaskList.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Create a new list
  Future<TaskList> createList({
    required String name,
    String? icon,
    String? color,
    String? parentId,
  }) async {
    final response = await _dio.post('/lists', data: {
      'name': name,
      'icon': icon,
      'color': color,
      'parent_id': parentId,
    });

    if (response.data['success'] == true) {
      return TaskList.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Search lists by name prefix
  Future<List<TaskList>> searchLists(String query, {String? parentId}) async {
    final response = await _dio.post('/lists/search', data: {
      'query': query,
      'parent_id': parentId,
    });

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => TaskList.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get tasks in a list
  Future<List<Task>> getListTasks(String listId, {bool includeSublists = false}) async {
    final response = await _dio.get('/lists/$listId/tasks', queryParameters: {
      'include_sublists': includeSublists.toString(),
    });

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Delete a list
  Future<void> deleteList(String listId) async {
    final response = await _dio.delete('/lists/$listId');

    if (response.data['success'] != true && response.statusCode != 204) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Archive a list
  Future<void> archiveList(String listId) async {
    final response = await _dio.post('/lists/$listId/archive');

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Unarchive a list
  Future<void> unarchiveList(String listId) async {
    final response = await _dio.post('/lists/$listId/unarchive');

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Cleanup empty lists (removes lists/sublists with 0 tasks)
  Future<Map<String, dynamic>> cleanupEmptyLists() async {
    final response = await _dio.post('/lists/cleanup-empty');

    if (response.data['success'] == true) {
      return response.data['data'] as Map<String, dynamic>;
    }

    throw ApiException.fromResponse(response.data);
  }

  // =====================================================
  // Attachment Endpoints
  // =====================================================

  /// Get attachments for a task
  Future<List<Attachment>> getAttachments(String taskId) async {
    final response = await _dio.get('/tasks/$taskId/attachments');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Create a link attachment
  Future<Attachment> createLinkAttachment(String taskId, {
    required String url,
    String? name,
  }) async {
    final response = await _dio.post('/tasks/$taskId/attachments', data: {
      'url': url,
      'name': name ?? url,
    });

    if (response.data['success'] == true) {
      return Attachment.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Delete an attachment
  Future<void> deleteAttachment(String taskId, String attachmentId) async {
    final response = await _dio.delete('/tasks/$taskId/attachments/$attachmentId');

    if (response.data['success'] != true && response.statusCode != 204) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Get presigned upload URL
  Future<Map<String, dynamic>> getPresignedUploadUrl(String taskId, {
    required String filename,
    required String mimeType,
    required int size,
  }) async {
    final response = await _dio.post('/tasks/$taskId/attachments/presign', data: {
      'filename': filename,
      'mime_type': mimeType,
      'size': size,
    });

    if (response.data['success'] == true) {
      return response.data['data'] as Map<String, dynamic>;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Upload a file attachment (stores in database)
  Future<Attachment> uploadFileAttachment(String taskId, {
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        fileBytes,
        filename: filename,
        headers: {
          'Content-Type': [mimeType],
        },
      ),
    });

    final response = await _dio.post(
      '/tasks/$taskId/attachments',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );

    if (response.data['success'] == true) {
      return Attachment.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  // =====================================================
  // AI Endpoints
  // =====================================================

  /// Get AI usage statistics for current user
  Future<AIUsageStats> getAIUsage() async {
    final response = await _dio.get('/ai/usage');

    if (response.data['success'] == true) {
      return AIUsageStats.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get user's subscription tier info
  Future<Map<String, dynamic>> getUserTier() async {
    final response = await _dio.get('/ai/tier');

    if (response.data['success'] == true) {
      return response.data['data'] as Map<String, dynamic>;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get pending AI drafts
  Future<List<AIDraft>> getAIDrafts() async {
    final response = await _dio.get('/ai/drafts');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => AIDraft.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Approve a draft (and optionally send it)
  Future<void> approveDraft(String draftId, {bool send = false}) async {
    final response = await _dio.post('/ai/drafts/$draftId/approve', data: {
      'send': send,
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Delete/cancel a draft
  Future<void> deleteDraft(String draftId) async {
    final response = await _dio.delete('/ai/drafts/$draftId');

    if (response.data['success'] != true && response.statusCode != 204) {
      throw ApiException.fromResponse(response.data);
    }
  }

  // =====================================================
  // Subscription Endpoints
  // =====================================================

  /// Get available subscription plans
  Future<List<SubscriptionPlan>> getPlans() async {
    final response = await _dio.get('/subscriptions/plans');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get current user's subscription
  Future<UserSubscription> getMySubscription() async {
    final response = await _dio.get('/subscriptions/me');

    if (response.data['success'] == true) {
      return UserSubscription.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Create checkout session for subscription
  Future<CheckoutResponse> createCheckout(String planId, {String? returnUrl}) async {
    final response = await _dio.post('/subscriptions/checkout', data: {
      'plan_id': planId,
      'return_url': returnUrl,
    });

    if (response.data['success'] == true) {
      return CheckoutResponse.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Cancel current subscription
  Future<void> cancelSubscription({String? reason}) async {
    final response = await _dio.post('/subscriptions/cancel', data: {
      'reason': reason,
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  // =====================================================
  // Admin Endpoints
  // =====================================================

  /// Check if current user is admin
  Future<bool> checkAdmin() async {
    try {
      final response = await _dio.get('/admin/check');
      return response.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Get list of users (admin only)
  Future<PaginatedResponse<AdminUser>> getAdminUsers({
    String? tier,
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get('/admin/users', queryParameters: {
      if (tier != null) 'tier': tier,
      'page': page,
      'page_size': pageSize,
    });

    if (response.data['success'] == true) {
      final users = (response.data['data'] as List)
          .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = response.data['meta'] != null
          ? ApiMeta.fromJson(response.data['meta'])
          : null;
      return PaginatedResponse(items: users, meta: meta);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get single user details (admin only)
  Future<AdminUser> getAdminUser(String userId) async {
    final response = await _dio.get('/admin/users/$userId');

    if (response.data['success'] == true) {
      return AdminUser.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update user subscription (admin only)
  Future<void> updateUserSubscription(String userId, {
    required String tier,
    String? planId,
    DateTime? expiresAt,
  }) async {
    final response = await _dio.put('/admin/users/$userId/subscription', data: {
      'tier': tier,
      'plan_id': planId,
      'expires_at': expiresAt?.toIso8601String(),
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Get list of orders (admin only)
  Future<PaginatedResponse<Order>> getAdminOrders({
    String? status,
    String? provider,
    String? tier,
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get('/admin/orders', queryParameters: {
      if (status != null) 'status': status,
      if (provider != null) 'provider': provider,
      if (tier != null) 'tier': tier,
      'page': page,
      'page_size': pageSize,
    });

    if (response.data['success'] == true) {
      final orders = (response.data['data'] as List)
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = response.data['meta'] != null
          ? ApiMeta.fromJson(response.data['meta'])
          : null;
      return PaginatedResponse(items: orders, meta: meta);
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
