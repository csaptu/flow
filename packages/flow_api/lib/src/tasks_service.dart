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
    DateTime? dueAt,
    bool hasDueTime = false,
    int? priority,
    List<String>? tags,
    String? parentId,
  }) async {
    final response = await _dio.post('/tasks', data: {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'has_due_time': hasDueTime,
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
  /// Set clearDueAt to true to remove the due date entirely
  Future<Task> update(String id, {
    String? title,
    String? description,
    DateTime? dueAt,
    bool? hasDueTime,
    bool clearDueAt = false,
    int? priority,
    String? status,
    List<String>? tags,
    String? groupId,
    String? parentId, // Set to empty string to remove parent
  }) async {
    final requestData = {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (clearDueAt) 'clear_due_at': true,
      if (dueAt != null && !clearDueAt) 'due_at': dueAt.toUtc().toIso8601String(),
      if (hasDueTime != null) 'has_due_time': hasDueTime,
      if (priority != null) 'priority': priority,
      if (status != null) 'status': status,
      if (tags != null) 'tags': tags,
      if (groupId != null) 'group_id': groupId,
      if (parentId != null) 'parent_id': parentId,
    };
    final response = await _dio.put('/tasks/$id', data: requestData);

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

  /// Reorder children of a task
  Future<void> reorderChildren(String parentId, List<String> taskIds) async {
    final response = await _dio.put(
      '/tasks/$parentId/children/reorder',
      data: {'task_ids': taskIds},
    );

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
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

  /// AI: Clean task title and/or description
  /// [field] can be 'title', 'description', or 'both' (default)
  Future<Task> aiClean(String id, {String field = 'both'}) async {
    final response = await _sharedDio.post(
      '/tasks/$id/ai/clean',
      queryParameters: {'field': field},
    );

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Clean just the task title
  Future<Task> aiCleanTitle(String id) async {
    return aiClean(id, field: 'title');
  }

  /// AI: Clean just the task description
  Future<Task> aiCleanDescription(String id) async {
    return aiClean(id, field: 'description');
  }

  /// AI: Revert to original human-written title
  Future<Task> aiRevert(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/revert');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
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

  /// AI: Check for duplicate tasks
  Future<AIDuplicatesResult> aiCheckDuplicates(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/check-duplicates');

    if (response.data['success'] == true) {
      return AIDuplicatesResult(
        task: Task.fromJson(response.data['data']['task']),
        duplicates: (response.data['data']['duplicates'] as List?)
                ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        reason: response.data['data']['reason'] as String?,
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Resolve/dismiss duplicate warning
  Future<Task> aiResolveDuplicate(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/resolve-duplicate');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Rate task complexity (1-10)
  Future<AIRateResult> aiRate(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/rate');

    if (response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>;
      return AIRateResult(
        task: Task.fromJson(data['task'] as Map<String, dynamic>),
        complexity: data['complexity'] as int,
        reason: data['reason'] as String?,
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Suggest reminder time
  Future<AIRemindResult> aiRemind(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/remind');

    if (response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>;
      return AIRemindResult(
        task: Task.fromJson(data['task'] as Map<String, dynamic>),
        reminderTime: DateTime.parse(data['reminder_time'] as String),
        reason: data['reason'] as String?,
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Draft an email based on task
  Future<AIDraftResult> aiEmail(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/email');

    if (response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>;
      final draft = data['draft'] as Map<String, dynamic>;
      return AIDraftResult(
        draftId: data['draft_id']?.toString(),
        draft: AIDraftContent(
          type: 'email',
          to: draft['to'] as String?,
          subject: draft['subject'] as String?,
          body: draft['body'] as String?,
        ),
      );
    }

    throw ApiException.fromResponse(response.data);
  }

  /// AI: Draft a calendar invite based on task
  Future<AIDraftResult> aiInvite(String id) async {
    final response = await _sharedDio.post('/tasks/$id/ai/invite');

    if (response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>;
      final draft = data['draft'] as Map<String, dynamic>;
      return AIDraftResult(
        draftId: data['draft_id']?.toString(),
        draft: AIDraftContent(
          type: 'calendar',
          title: draft['title'] as String?,
          body: draft['body'] as String?,
          startTime: draft['start_time'] as String?,
          endTime: draft['end_time'] as String?,
          attendees: (draft['attendees'] as List<dynamic>?)?.cast<String>() ?? [],
        ),
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
      final baseUrl = _dio.options.baseUrl;
      return (response.data['data'] as List)
          .map((e) {
            final attachment = Attachment.fromJson(e as Map<String, dynamic>);
            // Prepend base URL for relative URLs (file/image attachments)
            if (!attachment.url.startsWith('http') && !attachment.url.startsWith('data:')) {
              return attachment.copyWith(url: '$baseUrl${attachment.url}');
            }
            return attachment;
          })
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

    // 204 No Content is a success
    if (response.statusCode == 204) {
      return;
    }

    // Check for success response with data
    if (response.data is Map && response.data['success'] == true) {
      return;
    }

    throw ApiException.fromResponse(response.data);
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
  // Entity Management Endpoints
  // =====================================================

  /// Merge two entities by creating an alias relationship
  /// The source entity becomes an alias of the target (canonical) entity
  /// Tasks are NOT modified - the alias is resolved when displaying Smart Lists
  /// e.g., merge "Nam" into "Nam Tran" -> "Nam" becomes alias of "Nam Tran"
  Future<void> mergeEntities(String type, String fromValue, String toValue) async {
    final response = await _dio.post('/tasks/entities/merge', data: {
      'type': type,
      'from_value': fromValue,
      'to_value': toValue,
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Remove an entity from all tasks that have it
  /// This actually removes the entity chip from all affected tasks
  Future<void> removeEntity(String type, String value) async {
    final encodedValue = Uri.encodeComponent(value);
    final response = await _dio.delete('/tasks/entities/$type/$encodedValue');

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Get all aliases for a specific canonical entity
  Future<EntityAliasesResponse> getEntityAliases(String type, String value) async {
    final encodedValue = Uri.encodeComponent(value);
    final response = await _dio.get('/tasks/entities/$type/$encodedValue/aliases');

    if (response.data['success'] == true) {
      return EntityAliasesResponse.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Remove a single entity from a specific task
  /// Returns the updated task
  Future<Task> removeEntityFromTask(String taskId, String type, String value) async {
    final encodedValue = Uri.encodeComponent(value);
    final response = await _sharedDio.delete('/tasks/$taskId/entities/$type/$encodedValue');

    if (response.data['success'] == true) {
      return Task.fromJson(response.data['data']);
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
      // Convert to UTC for RFC3339 compatibility with Go backend
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'expires_at': expiresAt?.toUtc().toIso8601String(),
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

  // =====================================================
  // AI Profile Admin Endpoints
  // =====================================================

  /// Get user's AI profile (admin only)
  Future<UserAIProfile> getUserAIProfile(String userId) async {
    final response = await _dio.get('/admin/users/$userId/ai-profile');

    if (response.data['success'] == true) {
      return UserAIProfile.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update a single field in user's AI profile (admin only)
  Future<void> updateUserAIProfileField(
    String userId,
    String field,
    String value,
  ) async {
    final response = await _dio.put('/admin/users/$userId/ai-profile', data: {
      'field': field,
      'value': value,
    });

    if (response.data['success'] != true) {
      throw ApiException.fromResponse(response.data);
    }
  }

  /// Trigger AI profile refresh for a user (admin only)
  Future<UserAIProfile> refreshUserAIProfile(String userId) async {
    final response = await _dio.post('/admin/users/$userId/ai-profile/refresh');

    if (response.data['success'] == true) {
      return UserAIProfile.fromJson(response.data['data']);
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
