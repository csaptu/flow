import 'package:equatable/equatable.dart';

/// TaskList model (Bear-style #List/Sublist)
class TaskList extends Equatable {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final String? parentId;
  final int depth;
  final int taskCount;
  final String fullPath;
  final List<TaskList> children;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaskList({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.parentId,
    this.depth = 0,
    this.taskCount = 0,
    required this.fullPath,
    this.children = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskList.fromJson(Map<String, dynamic> json) {
    return TaskList(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      parentId: json['parent_id'] as String?,
      depth: json['depth'] as int? ?? 0,
      taskCount: json['task_count'] as int? ?? 0,
      fullPath: json['full_path'] as String? ?? json['name'] as String,
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => TaskList.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'parent_id': parentId,
        'depth': depth,
        'task_count': taskCount,
        'full_path': fullPath,
        'children': children.map((e) => e.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Check if this is a root list (no parent)
  bool get isRoot => parentId == null;

  /// Check if this is a sublist
  bool get isSublist => parentId != null;

  /// Check if this list has sublists
  bool get hasChildren => children.isNotEmpty;

  /// Get the hashtag representation (e.g., "#Work/Projects")
  String get hashtag => '#$fullPath';

  TaskList copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    String? parentId,
    int? depth,
    int? taskCount,
    String? fullPath,
    List<TaskList>? children,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskList(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      parentId: parentId ?? this.parentId,
      depth: depth ?? this.depth,
      taskCount: taskCount ?? this.taskCount,
      fullPath: fullPath ?? this.fullPath,
      children: children ?? this.children,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, fullPath];
}
