import 'package:equatable/equatable.dart';
import 'enums.dart';

/// Project progress
class ProjectProgress extends Equatable {
  final int totalNodes;
  final int completedNodes;
  final double percentage;

  const ProjectProgress({
    this.totalNodes = 0,
    this.completedNodes = 0,
    this.percentage = 0.0,
  });

  factory ProjectProgress.fromJson(Map<String, dynamic> json) {
    return ProjectProgress(
      totalNodes: json['total_nodes'] as int? ?? 0,
      completedNodes: json['completed_nodes'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [totalNodes, completedNodes, percentage];
}

/// Project model
class Project extends Equatable {
  final String id;
  final String name;
  final String? description;
  final ProjectStatus status;
  final Methodology methodology;
  final String? color;
  final String? icon;
  final DateTime? startDate;
  final DateTime? targetDate;
  final String ownerId;
  final ProjectProgress progress;
  final int memberCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    required this.id,
    required this.name,
    this.description,
    this.status = ProjectStatus.planning,
    this.methodology = Methodology.waterfall,
    this.color,
    this.icon,
    this.startDate,
    this.targetDate,
    required this.ownerId,
    this.progress = const ProjectProgress(),
    this.memberCount = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      status: ProjectStatus.fromString(json['status'] as String? ?? 'planning'),
      methodology:
          Methodology.fromString(json['methodology'] as String? ?? 'waterfall'),
      color: json['color'] as String?,
      icon: json['icon'] as String?,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      targetDate: json['target_date'] != null
          ? DateTime.parse(json['target_date'] as String)
          : null,
      ownerId: json['owner_id'] as String,
      progress: json['progress'] != null
          ? ProjectProgress.fromJson(json['progress'] as Map<String, dynamic>)
          : const ProjectProgress(),
      memberCount: json['member_count'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'status': status.toJson(),
        'methodology': methodology.name,
        'color': color,
        'icon': icon,
        'start_date': startDate?.toIso8601String(),
        'target_date': targetDate?.toIso8601String(),
        'owner_id': ownerId,
        'member_count': memberCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Project copyWith({
    String? name,
    String? description,
    ProjectStatus? status,
    Methodology? methodology,
    String? color,
    String? icon,
    DateTime? startDate,
    DateTime? targetDate,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      methodology: methodology ?? this.methodology,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      startDate: startDate ?? this.startDate,
      targetDate: targetDate ?? this.targetDate,
      ownerId: ownerId,
      progress: progress,
      memberCount: memberCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, status, progress, updatedAt];
}

/// Project member
class ProjectMember extends Equatable {
  final String id;
  final String userId;
  final MemberRole role;
  final String name;
  final String email;
  final String? avatarUrl;
  final DateTime joinedAt;

  const ProjectMember({
    required this.id,
    required this.userId,
    required this.role,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.joinedAt,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      role: MemberRole.fromString(json['role'] as String? ?? 'viewer'),
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, userId, role];
}
