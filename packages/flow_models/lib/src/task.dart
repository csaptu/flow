import 'package:equatable/equatable.dart';
import 'enums.dart';

/// Task step from AI decomposition
class TaskStep extends Equatable {
  final int step;
  final String action;
  final bool done;

  const TaskStep({
    required this.step,
    required this.action,
    this.done = false,
  });

  factory TaskStep.fromJson(Map<String, dynamic> json) {
    return TaskStep(
      step: json['step'] as int,
      action: json['action'] as String,
      done: json['done'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'step': step,
        'action': action,
        'done': done,
      };

  TaskStep copyWith({bool? done}) {
    return TaskStep(
      step: step,
      action: action,
      done: done ?? this.done,
    );
  }

  @override
  List<Object?> get props => [step, action, done];
}

/// Task model
class Task extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String? aiSummary;
  final List<TaskStep> aiSteps;
  final TaskStatus status;
  final Priority priority;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final List<String> tags;
  final String? parentId;
  final int depth;
  final int complexity;
  final String? groupId;
  final String? groupName;
  final bool hasChildren;
  final int childrenCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Task({
    required this.id,
    required this.title,
    this.description,
    this.aiSummary,
    this.aiSteps = const [],
    this.status = TaskStatus.pending,
    this.priority = Priority.none,
    this.dueDate,
    this.completedAt,
    this.tags = const [],
    this.parentId,
    this.depth = 0,
    this.complexity = 0,
    this.groupId,
    this.groupName,
    this.hasChildren = false,
    this.childrenCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      aiSummary: json['ai_summary'] as String?,
      aiSteps: (json['ai_steps'] as List<dynamic>?)
              ?.map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: TaskStatus.fromString(json['status'] as String? ?? 'pending'),
      priority: Priority.fromInt(json['priority'] as int? ?? 0),
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      parentId: json['parent_id'] as String?,
      depth: json['depth'] as int? ?? 0,
      complexity: json['complexity'] as int? ?? 0,
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String?,
      hasChildren: json['has_children'] as bool? ?? false,
      childrenCount: json['children_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'ai_summary': aiSummary,
        'ai_steps': aiSteps.map((e) => e.toJson()).toList(),
        'status': status.toJson(),
        'priority': priority.value,
        'due_date': dueDate?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'tags': tags,
        'parent_id': parentId,
        'depth': depth,
        'complexity': complexity,
        'group_id': groupId,
        'group_name': groupName,
        'has_children': hasChildren,
        'children_count': childrenCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  bool get isCompleted => status == TaskStatus.completed;

  bool get isOverdue =>
      dueDate != null && DateTime.now().isAfter(dueDate!) && !isCompleted;

  double get progress {
    if (aiSteps.isEmpty) return isCompleted ? 100.0 : 0.0;
    final done = aiSteps.where((s) => s.done).length;
    return (done / aiSteps.length) * 100.0;
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? aiSummary,
    List<TaskStep>? aiSteps,
    TaskStatus? status,
    Priority? priority,
    DateTime? dueDate,
    DateTime? completedAt,
    List<String>? tags,
    String? parentId,
    int? depth,
    int? complexity,
    String? groupId,
    String? groupName,
    bool? hasChildren,
    int? childrenCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      aiSummary: aiSummary ?? this.aiSummary,
      aiSteps: aiSteps ?? this.aiSteps,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      tags: tags ?? this.tags,
      parentId: parentId ?? this.parentId,
      depth: depth ?? this.depth,
      complexity: complexity ?? this.complexity,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      hasChildren: hasChildren ?? this.hasChildren,
      childrenCount: childrenCount ?? this.childrenCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, title, status, priority, dueDate, updatedAt];
}

/// Task group model
class TaskGroup extends Equatable {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final bool aiCreated;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaskGroup({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.aiCreated = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskGroup.fromJson(Map<String, dynamic> json) {
    return TaskGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      aiCreated: json['ai_created'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, name];
}
