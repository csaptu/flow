import 'package:equatable/equatable.dart';
import 'enums.dart';

/// User subscription tier
enum UserTier {
  free,
  light,
  premium;

  static UserTier fromString(String value) {
    switch (value.toLowerCase()) {
      case 'light':
        return UserTier.light;
      case 'premium':
        return UserTier.premium;
      default:
        return UserTier.free;
    }
  }
}

// Note: AISetting enum is defined in enums.dart
// Note: AIPreferences class is defined in user.dart

/// AI feature type - matches the plan document
enum AIFeature {
  // Free tier features
  cleanTitle,
  cleanDescription,
  smartDueDate,

  // Light tier features
  decompose,
  complexity,
  entityExtraction,
  recurringDetection,
  autoGroup,
  reminder,
  draftEmail,
  draftCalendar,

  // Premium tier features (execution)
  sendEmail,
  sendCalendar;

  String get key {
    switch (this) {
      case AIFeature.cleanTitle:
        return 'clean_title';
      case AIFeature.cleanDescription:
        return 'clean_description';
      case AIFeature.smartDueDate:
        return 'smart_due_date';
      case AIFeature.decompose:
        return 'decompose';
      case AIFeature.complexity:
        return 'complexity';
      case AIFeature.entityExtraction:
        return 'entity_extraction';
      case AIFeature.recurringDetection:
        return 'recurring_detection';
      case AIFeature.autoGroup:
        return 'auto_group';
      case AIFeature.reminder:
        return 'reminder';
      case AIFeature.draftEmail:
        return 'draft_email';
      case AIFeature.draftCalendar:
        return 'draft_calendar';
      case AIFeature.sendEmail:
        return 'send_email';
      case AIFeature.sendCalendar:
        return 'send_calendar';
    }
  }

  /// Display name for the feature
  String get displayName {
    switch (this) {
      case AIFeature.cleanTitle:
        return 'Clean Title';
      case AIFeature.cleanDescription:
        return 'Clean Description';
      case AIFeature.smartDueDate:
        return 'Smart Due Dates';
      case AIFeature.decompose:
        return 'Decompose Tasks';
      case AIFeature.complexity:
        return 'Complexity Check';
      case AIFeature.entityExtraction:
        return 'Entity Extraction';
      case AIFeature.recurringDetection:
        return 'Recurring Detection';
      case AIFeature.autoGroup:
        return 'Auto-Group';
      case AIFeature.reminder:
        return 'Reminder';
      case AIFeature.draftEmail:
        return 'Draft Email';
      case AIFeature.draftCalendar:
        return 'Draft Calendar';
      case AIFeature.sendEmail:
        return 'Send Email';
      case AIFeature.sendCalendar:
        return 'Send Calendar';
    }
  }

  /// Required tier for this feature
  UserTier get requiredTier {
    switch (this) {
      case AIFeature.cleanTitle:
      case AIFeature.cleanDescription:
      case AIFeature.smartDueDate:
        return UserTier.free;
      case AIFeature.decompose:
      case AIFeature.complexity:
      case AIFeature.entityExtraction:
      case AIFeature.recurringDetection:
      case AIFeature.autoGroup:
      case AIFeature.reminder:
      case AIFeature.draftEmail:
      case AIFeature.draftCalendar:
        return UserTier.light;
      case AIFeature.sendEmail:
      case AIFeature.sendCalendar:
        return UserTier.premium;
    }
  }

  /// Default setting for this feature
  AISetting get defaultSetting {
    switch (this) {
      case AIFeature.cleanTitle:
      case AIFeature.cleanDescription:
      case AIFeature.smartDueDate:
      case AIFeature.complexity:
      case AIFeature.entityExtraction:
        return AISetting.auto;
      case AIFeature.decompose:
      case AIFeature.recurringDetection:
      case AIFeature.autoGroup:
      case AIFeature.reminder:
      case AIFeature.draftEmail:
      case AIFeature.draftCalendar:
      case AIFeature.sendEmail:
      case AIFeature.sendCalendar:
        return AISetting.ask;
    }
  }

  /// Description of what this feature does
  String get description {
    switch (this) {
      case AIFeature.cleanTitle:
        return 'Shorten titles to <8 words';
      case AIFeature.cleanDescription:
        return 'Summarize descriptions to <15 words';
      case AIFeature.smartDueDate:
        return 'Parse "tomorrow", "next week" etc';
      case AIFeature.decompose:
        return 'Break down tasks into 2-5 steps';
      case AIFeature.complexity:
        return 'Score task complexity 1-10';
      case AIFeature.entityExtraction:
        return 'Find people mentioned in tasks';
      case AIFeature.recurringDetection:
        return 'Detect recurring patterns';
      case AIFeature.autoGroup:
        return 'Group similar tasks together';
      case AIFeature.reminder:
        return 'Suggest reminder times';
      case AIFeature.draftEmail:
        return 'Generate email drafts from tasks';
      case AIFeature.draftCalendar:
        return 'Generate calendar invites';
      case AIFeature.sendEmail:
        return 'Send emails via connected account';
      case AIFeature.sendCalendar:
        return 'Create events via connected calendar';
    }
  }
}

// Note: AIPreferences class is defined in user.dart

/// AI usage statistics
class AIUsageStats extends Equatable {
  final UserTier tier;
  final Map<String, int> usage;
  final Map<String, int> limits;

  const AIUsageStats({
    required this.tier,
    required this.usage,
    required this.limits,
  });

  factory AIUsageStats.fromJson(Map<String, dynamic> json) {
    return AIUsageStats(
      tier: UserTier.fromString(json['tier'] as String? ?? 'free'),
      usage: (json['usage'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      limits: (json['limits'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
    );
  }

  /// Get remaining uses for a feature
  int remainingUses(AIFeature feature) {
    final limit = limits[feature.key];
    if (limit == null || limit == -1) return -1; // unlimited
    final used = usage[feature.key] ?? 0;
    return (limit - used).clamp(0, limit);
  }

  /// Check if feature is available (has remaining uses)
  bool canUse(AIFeature feature) {
    if (!limits.containsKey(feature.key)) return false;
    final remaining = remainingUses(feature);
    return remaining == -1 || remaining > 0;
  }

  @override
  List<Object?> get props => [tier, usage, limits];
}

/// AI draft content
class AIDraft extends Equatable {
  final String id;
  final String taskId;
  final String type; // 'email' or 'calendar'
  final Map<String, dynamic> content;
  final DateTime createdAt;

  const AIDraft({
    required this.id,
    required this.taskId,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  factory AIDraft.fromJson(Map<String, dynamic> json) {
    return AIDraft(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      type: json['type'] as String,
      content: json['content'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// For email drafts
  String? get to => content['to'] as String?;
  String? get subject => content['subject'] as String?;
  String? get body => content['body'] as String?;

  /// For calendar drafts
  String? get title => content['title'] as String?;
  String? get startTime => content['start_time'] as String?;
  String? get endTime => content['end_time'] as String?;
  List<String> get attendees =>
      (content['attendees'] as List<dynamic>?)?.cast<String>() ?? [];

  @override
  List<Object?> get props => [id, taskId, type];
}

/// AI Decompose result (task breakdown into subtasks)
class AIDecomposeResult extends Equatable {
  final dynamic task; // Task object (parent)
  final List<dynamic> subtasks; // List of created subtask objects

  const AIDecomposeResult({
    required this.task,
    required this.subtasks,
  });

  @override
  List<Object?> get props => [task, subtasks];
}

/// AI Rate result (complexity rating)
class AIRateResult extends Equatable {
  final dynamic task; // Task object
  final int complexity;
  final String reason;

  const AIRateResult({
    required this.task,
    required this.complexity,
    required this.reason,
  });

  @override
  List<Object?> get props => [complexity, reason];
}

/// AI Entity extracted from task
class AIEntity extends Equatable {
  final String type; // person, date, location, organization, email, phone
  final String value;

  const AIEntity({
    required this.type,
    required this.value,
  });

  factory AIEntity.fromJson(Map<String, dynamic> json) {
    return AIEntity(
      type: json['type'] as String,
      value: json['value'] as String,
    );
  }

  @override
  List<Object?> get props => [type, value];
}

/// Smart List item (aggregated entity with task count)
class SmartListItem extends Equatable {
  final String type; // person, location, organization
  final String value;
  final int count; // number of tasks with this entity

  const SmartListItem({
    required this.type,
    required this.value,
    required this.count,
  });

  factory SmartListItem.fromJson(Map<String, dynamic> json) {
    return SmartListItem(
      type: json['type'] as String,
      value: json['value'] as String,
      count: json['count'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [type, value, count];
}

/// AI Extract result (entity extraction)
class AIExtractResult extends Equatable {
  final dynamic task; // Task object
  final List<AIEntity> entities;

  const AIExtractResult({
    required this.task,
    required this.entities,
  });

  @override
  List<Object?> get props => [entities];
}

/// AI Remind result (suggested reminder time)
class AIRemindResult extends Equatable {
  final dynamic task; // Task object
  final DateTime reminderTime;
  final String reason;

  const AIRemindResult({
    required this.task,
    required this.reminderTime,
    required this.reason,
  });

  @override
  List<Object?> get props => [reminderTime, reason];
}

/// AI Draft result (email or calendar draft)
class AIDraftResult extends Equatable {
  final String? draftId;
  final AIDraftContent draft;

  const AIDraftResult({
    this.draftId,
    required this.draft,
  });

  @override
  List<Object?> get props => [draftId, draft];
}

/// AI Draft content (used in results)
class AIDraftContent extends Equatable {
  final String type; // 'email' or 'calendar'
  final String? to;
  final String? subject;
  final String? body;
  final String? title;
  final String? startTime;
  final String? endTime;
  final List<String> attendees;

  const AIDraftContent({
    required this.type,
    this.to,
    this.subject,
    this.body,
    this.title,
    this.startTime,
    this.endTime,
    this.attendees = const [],
  });

  factory AIDraftContent.fromJson(Map<String, dynamic> json) {
    return AIDraftContent(
      type: json['type'] as String? ?? 'email',
      to: json['to'] as String?,
      subject: json['subject'] as String?,
      body: json['body'] as String?,
      title: json['title'] as String?,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      attendees: (json['attendees'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  @override
  List<Object?> get props => [type, to, subject, body, title, startTime, endTime, attendees];
}
