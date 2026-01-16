import 'package:equatable/equatable.dart';

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

/// AI feature type
enum AIFeature {
  cleanTitle,
  cleanDescription,
  smartDueDate,
  reminder,
  decompose,
  complexity,
  entityExtraction,
  recurringDetection,
  autoGroup,
  draftEmail,
  draftCalendar;

  String get key {
    switch (this) {
      case AIFeature.cleanTitle:
        return 'clean_title';
      case AIFeature.cleanDescription:
        return 'clean_description';
      case AIFeature.smartDueDate:
        return 'smart_due_date';
      case AIFeature.reminder:
        return 'reminder';
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
      case AIFeature.draftEmail:
        return 'draft_email';
      case AIFeature.draftCalendar:
        return 'draft_calendar';
    }
  }
}

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
