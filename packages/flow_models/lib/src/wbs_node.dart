import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'task.dart';

/// WBS Node model
class WBSNode extends Equatable {
  final String id;
  final String projectId;
  final String? parentId;
  final String title;
  final String? description;
  final TaskStatus status;
  final Priority priority;
  final double progress;
  final int depth;
  final String path;
  final int position;
  final String? assigneeId;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final int? duration;
  final bool isCritical;
  final bool hasChildren;
  final List<TaskStep> aiSteps;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WBSNode({
    required this.id,
    required this.projectId,
    this.parentId,
    required this.title,
    this.description,
    this.status = TaskStatus.pending,
    this.priority = Priority.none,
    this.progress = 0,
    this.depth = 0,
    this.path = '',
    this.position = 0,
    this.assigneeId,
    this.plannedStart,
    this.plannedEnd,
    this.duration,
    this.isCritical = false,
    this.hasChildren = false,
    this.aiSteps = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory WBSNode.fromJson(Map<String, dynamic> json) {
    return WBSNode(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      parentId: json['parent_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: TaskStatus.fromString(json['status'] as String? ?? 'pending'),
      priority: Priority.fromInt(json['priority'] as int? ?? 0),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      depth: json['depth'] as int? ?? 0,
      path: json['path'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      assigneeId: json['assignee_id'] as String?,
      plannedStart: json['planned_start'] != null
          ? DateTime.parse(json['planned_start'] as String)
          : null,
      plannedEnd: json['planned_end'] != null
          ? DateTime.parse(json['planned_end'] as String)
          : null,
      duration: json['duration'] as int?,
      isCritical: json['is_critical'] as bool? ?? false,
      hasChildren: json['has_children'] as bool? ?? false,
      aiSteps: (json['ai_steps'] as List<dynamic>?)
              ?.map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'parent_id': parentId,
        'title': title,
        'description': description,
        'status': status.toJson(),
        'priority': priority.value,
        'progress': progress,
        'depth': depth,
        'path': path,
        'position': position,
        'assignee_id': assigneeId,
        'planned_start': plannedStart?.toIso8601String(),
        'planned_end': plannedEnd?.toIso8601String(),
        'duration': duration,
        'is_critical': isCritical,
        'has_children': hasChildren,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  bool get isCompleted => status == TaskStatus.completed;
  bool get isMilestone => duration == 0;

  WBSNode copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    Priority? priority,
    double? progress,
    String? assigneeId,
    DateTime? plannedStart,
    DateTime? plannedEnd,
  }) {
    return WBSNode(
      id: id,
      projectId: projectId,
      parentId: parentId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      progress: progress ?? this.progress,
      depth: depth,
      path: path,
      position: position,
      assigneeId: assigneeId ?? this.assigneeId,
      plannedStart: plannedStart ?? this.plannedStart,
      plannedEnd: plannedEnd ?? this.plannedEnd,
      duration: duration,
      isCritical: isCritical,
      hasChildren: hasChildren,
      aiSteps: aiSteps,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, title, status, progress, updatedAt];
}

/// Gantt bar for visualization
class GanttBar extends Equatable {
  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final double progress;
  final String? assigneeId;
  final bool isCritical;
  final bool isMilestone;
  final String? parentId;
  final List<String> dependencies;

  const GanttBar({
    required this.id,
    required this.title,
    this.start,
    this.end,
    this.progress = 0,
    this.assigneeId,
    this.isCritical = false,
    this.isMilestone = false,
    this.parentId,
    this.dependencies = const [],
  });

  factory GanttBar.fromJson(Map<String, dynamic> json) {
    return GanttBar(
      id: json['id'] as String,
      title: json['title'] as String,
      start: json['start'] != null
          ? DateTime.parse(json['start'] as String)
          : null,
      end: json['end'] != null ? DateTime.parse(json['end'] as String) : null,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      assigneeId: json['assignee_id'] as String?,
      isCritical: json['is_critical'] as bool? ?? false,
      isMilestone: json['is_milestone'] as bool? ?? false,
      parentId: json['parent_id'] as String?,
      dependencies:
          (json['dependencies'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  @override
  List<Object?> get props => [id, title, start, end, progress];
}

/// WBS Dependency
class WBSDependency extends Equatable {
  final String id;
  final String predecessorId;
  final String successorId;
  final DependencyType dependencyType;
  final int lagDays;
  final DateTime createdAt;

  const WBSDependency({
    required this.id,
    required this.predecessorId,
    required this.successorId,
    this.dependencyType = DependencyType.fs,
    this.lagDays = 0,
    required this.createdAt,
  });

  factory WBSDependency.fromJson(Map<String, dynamic> json) {
    return WBSDependency(
      id: json['id'] as String,
      predecessorId: json['predecessor_id'] as String,
      successorId: json['successor_id'] as String,
      dependencyType:
          DependencyType.fromString(json['dependency_type'] as String? ?? 'FS'),
      lagDays: json['lag_days'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, predecessorId, successorId, dependencyType];
}
