import 'package:equatable/equatable.dart';
import 'ai.dart';
import 'enums.dart';

/// Parse a date string and convert to local timezone
/// This ensures dates are always compared in the user's local timezone
DateTime _parseToLocal(String dateString) {
  final parsed = DateTime.parse(dateString);
  // If the date is in UTC, convert to local
  if (parsed.isUtc) {
    return parsed.toLocal();
  }
  return parsed;
}

/// Task model
class Task extends Equatable {
  final String id;
  final String title; // User's original input (always preserved)
  final String? description; // User's original input (always preserved)
  final TaskStatus status;
  final Priority priority;
  final DateTime? dueAt; // Full timestamp with timezone
  final bool hasDueTime; // true = specific time matters
  final DateTime? completedAt;
  final List<String> tags;
  final String? parentId;
  final int depth;
  final int sortOrder; // Order within parent (for subtasks)
  final int complexity;
  final bool hasChildren;
  final int childrenCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  // AI cleaned versions (null = not cleaned, text = cleaned version to display)
  final String? aiCleanedTitle;
  final String? aiCleanedDescription;
  // Display fields (computed by API: ai_cleaned_title ?? title)
  final String displayTitle;
  final String? displayDescription;
  // Flag to prevent auto-cleanup after user reverts
  final bool skipAutoCleanup;
  // AI-extracted entities (people, locations, organizations)
  final List<AIEntity> entities;
  // Duplicate detection - IDs of tasks that may be duplicates
  final List<String> duplicateOf;
  // Whether the user has resolved/dismissed the duplicate warning
  final bool duplicateResolved;

  const Task({
    required this.id,
    required this.title,
    this.description,
    this.status = TaskStatus.pending,
    this.priority = Priority.none,
    this.dueAt,
    this.hasDueTime = false,
    this.completedAt,
    this.tags = const [],
    this.parentId,
    this.depth = 0,
    this.sortOrder = 0,
    this.complexity = 0,
    this.hasChildren = false,
    this.childrenCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.aiCleanedTitle,
    this.aiCleanedDescription,
    String? displayTitle,
    this.displayDescription,
    this.skipAutoCleanup = false,
    this.entities = const [],
    this.duplicateOf = const [],
    this.duplicateResolved = false,
  }) : displayTitle = displayTitle ?? title; // Default to title if not provided

  /// Returns true if the title was cleaned by AI (has AI cleaned version)
  bool get titleWasCleaned => aiCleanedTitle != null && aiCleanedTitle!.isNotEmpty;

  /// Returns true if the description was cleaned by AI (has AI cleaned version)
  bool get descriptionWasCleaned => aiCleanedDescription != null && aiCleanedDescription!.isNotEmpty;

  factory Task.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String;
    return Task(
      id: json['id'] as String,
      title: title,
      description: json['description'] as String?,
      status: TaskStatus.fromString(json['status'] as String? ?? 'pending'),
      priority: Priority.fromInt(json['priority'] as int? ?? 0),
      dueAt: json['due_at'] != null ? _parseToLocal(json['due_at'] as String) : null,
      hasDueTime: json['has_due_time'] as bool? ?? false,
      completedAt: json['completed_at'] != null
          ? _parseToLocal(json['completed_at'] as String)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      parentId: json['parent_id'] as String?,
      depth: json['depth'] as int? ?? 0,
      sortOrder: json['sort_order'] as int? ?? 0,
      complexity: json['complexity'] as int? ?? 0,
      hasChildren: json['has_children'] as bool? ?? false,
      childrenCount: json['children_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      aiCleanedTitle: json['ai_cleaned_title'] as String?,
      aiCleanedDescription: json['ai_cleaned_description'] as String?,
      displayTitle: json['display_title'] as String? ?? title,
      displayDescription: json['display_description'] as String?,
      skipAutoCleanup: json['skip_auto_cleanup'] as bool? ?? false,
      entities: (json['entities'] as List<dynamic>?)
              ?.map((e) => AIEntity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      duplicateOf: (json['duplicate_of'] as List<dynamic>?)?.cast<String>() ?? [],
      duplicateResolved: json['duplicate_resolved'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.toJson(),
        'priority': priority.value,
        'due_at': dueAt?.toUtc().toIso8601String(),
        'has_due_time': hasDueTime,
        'completed_at': completedAt?.toIso8601String(),
        'tags': tags,
        'parent_id': parentId,
        'depth': depth,
        'sort_order': sortOrder,
        'complexity': complexity,
        'has_children': hasChildren,
        'children_count': childrenCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'ai_cleaned_title': aiCleanedTitle,
        'ai_cleaned_description': aiCleanedDescription,
        'display_title': displayTitle,
        'display_description': displayDescription,
        'skip_auto_cleanup': skipAutoCleanup,
        'entities': entities.map((e) => {'type': e.type, 'value': e.value}).toList(),
        'duplicate_of': duplicateOf,
        'duplicate_resolved': duplicateResolved,
      };

  bool get isCompleted => status == TaskStatus.completed;

  /// Check if the due date has a specific time set
  bool get hasSpecificTime => hasDueTime;

  /// A task is overdue if:
  /// - It has a due date in the past (before today), OR
  /// - It's due today with a specific time that has already passed
  ///
  /// A task due "Today" without a specific time is NOT overdue
  /// (it means "due sometime today")
  bool get isOverdue {
    if (dueAt == null || isCompleted) return false;

    final now = DateTime.now();

    // If has specific time, check if that exact time has passed
    if (hasDueTime) {
      return now.isAfter(dueAt!);
    }

    // Date-only: only overdue if date is strictly before today
    final today = DateTime(now.year, now.month, now.day);
    final dueDateOnly = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
    return dueDateOnly.isBefore(today);
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    TaskStatus? status,
    Priority? priority,
    DateTime? dueAt,
    bool? hasDueTime,
    DateTime? completedAt,
    List<String>? tags,
    String? parentId,
    int? depth,
    int? sortOrder,
    int? complexity,
    bool? hasChildren,
    int? childrenCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? aiCleanedTitle,
    String? aiCleanedDescription,
    String? displayTitle,
    String? displayDescription,
    bool? skipAutoCleanup,
    List<AIEntity>? entities,
    List<String>? duplicateOf,
    bool? duplicateResolved,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueAt: dueAt ?? this.dueAt,
      hasDueTime: hasDueTime ?? this.hasDueTime,
      completedAt: completedAt ?? this.completedAt,
      tags: tags ?? this.tags,
      parentId: parentId ?? this.parentId,
      depth: depth ?? this.depth,
      sortOrder: sortOrder ?? this.sortOrder,
      complexity: complexity ?? this.complexity,
      hasChildren: hasChildren ?? this.hasChildren,
      childrenCount: childrenCount ?? this.childrenCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      aiCleanedTitle: aiCleanedTitle ?? this.aiCleanedTitle,
      aiCleanedDescription: aiCleanedDescription ?? this.aiCleanedDescription,
      displayTitle: displayTitle ?? this.displayTitle,
      displayDescription: displayDescription ?? this.displayDescription,
      skipAutoCleanup: skipAutoCleanup ?? this.skipAutoCleanup,
      entities: entities ?? this.entities,
      duplicateOf: duplicateOf ?? this.duplicateOf,
      duplicateResolved: duplicateResolved ?? this.duplicateResolved,
    );
  }

  /// Returns true if the task has unresolved duplicate warnings
  bool get hasDuplicateWarning => duplicateOf.isNotEmpty && !duplicateResolved;

  @override
  List<Object?> get props => [id, title, status, priority, dueAt, hasDueTime, sortOrder, updatedAt, entities, duplicateOf, duplicateResolved];
}
