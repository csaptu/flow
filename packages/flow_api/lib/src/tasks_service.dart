import 'package:dio/dio.dart';
import 'package:flow_models/flow_models.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Tasks service
class TasksService {
  final FlowApiClient _client;

  TasksService(this._client);

  Dio get _dio => _client.tasksClient;

  // AI operations use the shared service
  Dio get _sharedDio => _client.sharedClient;

  /// Create a new task
  Future<Task> create({
    String? id, // Client-provided ID for offline-first sync
    required String title,
    String? description,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
    String? parentId,
  }) async {
    final response = await _dio.post('/tasks', data: {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'due_date': _formatDueDate(dueDate),
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
    String? parentId, // Set to empty string to remove parent
  }) async {
    final response = await _dio.put('/tasks/$id', data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (dueDate != null) 'due_date': _formatDueDate(dueDate),
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (tags != null) 'tags': tags,
      if (groupId != null) 'group_id': groupId,
      if (parentId != null) 'parent_id': parentId,
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
  Future<AIDecomposeResult> aiDecompose(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/decompose');

    if (response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>;

      // Check if new format (task + subtasks) or old format (just task fields)
      Task task;
      List<Task> subtasks = [];

      if (data.containsKey('task') && data['task'] != null) {
        // New format: { task: {...}, subtasks: [...] }
        task = Task.fromJson(data['task'] as Map<String, dynamic>);
        final subtasksData = data['subtasks'] as List?;
        if (subtasksData != null) {
          subtasks = subtasksData
              .map((e) => Task.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } else {
        // Old format: task fields directly in data
        task = Task.fromJson(data);
      }

      return AIDecomposeResult(task: task, subtasks: subtasks);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Clean task title and description
  Future<Task> aiClean(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/clean');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Revert to original human-written title
  Future<Task> aiRevert(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/revert');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Rate task complexity (1-10)
  Future<AIRateResult> aiRate(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/rate');

    if (response.data['success'] == true) {
      return AIRateResult(
        task: Task.fromJson(response.data['data']['task']),
        complexity: response.data['data']['complexity'] as int,
        reason: response.data['data']['reason'] as String,
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Extract entities from task
  Future<AIExtractResult> aiExtract(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/extract');

    if (response.data['success'] == true) {
      return AIExtractResult(
        task: Task.fromJson(response.data['data']['task']),
        entities: (response.data['data']['entities'] as List?)
                ?.map((e) => AIEntity.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Suggest reminder time for task
  Future<AIRemindResult> aiRemind(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/remind');

    if (response.data['success'] == true) {
      return AIRemindResult(
        task: Task.fromJson(response.data['data']['task']),
        reminderTime: DateTime.parse(response.data['data']['reminder_time']),
        reason: response.data['data']['reason'] as String,
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Draft email based on task
  Future<AIDraftResult> aiEmail(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/email');

    if (response.data['success'] == true) {
      return AIDraftResult(
        draftId: response.data['data']['draft_id'] as String?,
        draft: AIDraftContent.fromJson(response.data['data']['draft']),
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Draft calendar invite based on task
  Future<AIDraftResult> aiInvite(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/invite');

    if (response.data['success'] == true) {
      return AIDraftResult(
        draftId: response.data['data']['draft_id'] as String?,
        draft: AIDraftContent.fromJson(response.data['data']['draft']),
      );
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
    final response = await _sharedDio.get('/ai/usage');

    if (response.data['success'] == true) {
      return AIUsageStats.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get user's subscription tier info
  Future<Map<String, dynamic>> getUserTier() async {
    final response = await _sharedDio.get('/ai/tier');

    if (response.data['success'] == true) {
      return response.data['data'] as Map<String, dynamic>;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get pending AI drafts
  Future<List<AIDraft>> getAIDrafts() async {
    final response = await _sharedDio.get('/ai/drafts');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => AIDraft.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Approve a draft (and optionally send it)
  Future<void> approveDraft(String draftId, {bool send = false}) async {
    final response = await _sharedDio.post('/ai/drafts/$draftId/approve', data: {
      'send': send,
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Delete/cancel a draft
  Future<void> deleteDraft(String draftId) async {
    final response = await _sharedDio.delete('/ai/drafts/$draftId');

    if (response.data['success'] != true && response.statusCode != 204) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Get aggregated entities for Smart Lists
  Future<Map<String, List<SmartListItem>>> getEntities() async {
    final response = await _sharedDio.get('/tasks/entities');

    if (response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>? ?? {};
      final result = <String, List<SmartListItem>>{};

      for (final entry in data.entries) {
        final items = (entry.value as List?)
                ?.map((e) => SmartListItem.fromJson({
                      'type': entry.key,
                      ...(e as Map<String, dynamic>),
                    }))
                .toList() ??
            [];
        if (items.isNotEmpty) {
          result[entry.key] = items;
        }
      }

      return result;
    }

    throw ApiException.fromResponse(response.data);
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
    DateTime? startsAt,
    DateTime? expiresAt,
  }) async {
    final response = await _dio.put('/admin/users/$userId/subscription', data: {
      'tier': tier,
      'plan_id': planId,
      'starts_at': startsAt?.toIso8601String(),
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

  /// Get all AI prompt configurations (admin only)
  Future<List<AIPromptConfig>> getAIConfigs() async {
    final response = await _dio.get('/admin/ai-configs');

    if (response.data['success'] == true) {
      return (response.data['data'] as List)
          .map((e) => AIPromptConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update an AI prompt configuration (admin only)
  Future<void> updateAIConfig(String key, String value) async {
    final response = await _dio.put('/admin/ai-configs/$key', data: {
      'value': value,
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
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

/// Format due date for API.
/// If the date has no specific time (midnight local), send it as local time to preserve the date.
/// If it has a specific time, send as UTC for accuracy.
String? _formatDueDate(DateTime? date) {
  if (date == null) return null;

  // Convert to local time to check if it's midnight
  final local = date.toLocal();
  final isDateOnly = local.hour == 0 && local.minute == 0 && local.second == 0;

  if (isDateOnly) {
    // Send as local midnight to preserve the date across timezones
    // Format: 2026-01-20T00:00:00+07:00 (with local offset)
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final dateStr = '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    return '${dateStr}T00:00:00$sign$hours:$minutes';
  } else {
    // Has specific time - send as UTC for accuracy
    return date.toUtc().toIso8601String();
  }
}
