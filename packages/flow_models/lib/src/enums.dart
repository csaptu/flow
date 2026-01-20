/// Status of a task or WBS node
enum TaskStatus {
  pending,
  inProgress,
  completed,
  cancelled,
  archived;

  static TaskStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return TaskStatus.pending;
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      case 'archived':
        return TaskStatus.archived;
      default:
        return TaskStatus.pending;
    }
  }

  String toJson() {
    switch (this) {
      case TaskStatus.pending:
        return 'pending';
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.cancelled:
        return 'cancelled';
      case TaskStatus.archived:
        return 'archived';
    }
  }
}

/// Priority level
enum Priority {
  none(0),
  low(1),
  medium(2),
  high(3),
  urgent(4);

  final int value;
  const Priority(this.value);

  static Priority fromInt(int value) {
    return Priority.values.firstWhere(
      (p) => p.value == value,
      orElse: () => Priority.none,
    );
  }
}

/// Project status
enum ProjectStatus {
  planning,
  active,
  onHold,
  completed,
  cancelled;

  static ProjectStatus fromString(String value) {
    switch (value) {
      case 'planning':
        return ProjectStatus.planning;
      case 'active':
        return ProjectStatus.active;
      case 'on_hold':
        return ProjectStatus.onHold;
      case 'completed':
        return ProjectStatus.completed;
      case 'cancelled':
        return ProjectStatus.cancelled;
      default:
        return ProjectStatus.planning;
    }
  }

  String toJson() {
    switch (this) {
      case ProjectStatus.planning:
        return 'planning';
      case ProjectStatus.active:
        return 'active';
      case ProjectStatus.onHold:
        return 'on_hold';
      case ProjectStatus.completed:
        return 'completed';
      case ProjectStatus.cancelled:
        return 'cancelled';
    }
  }
}

/// Project methodology
enum Methodology {
  waterfall,
  agile,
  hybrid,
  kanban;

  static Methodology fromString(String value) {
    return Methodology.values.firstWhere(
      (m) => m.name == value,
      orElse: () => Methodology.waterfall,
    );
  }
}

/// Project member role
enum MemberRole {
  owner,
  admin,
  member,
  viewer;

  static MemberRole fromString(String value) {
    return MemberRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => MemberRole.viewer,
    );
  }
}

/// Dependency type for WBS nodes
enum DependencyType {
  fs('FS'), // Finish-to-Start
  ss('SS'), // Start-to-Start
  ff('FF'), // Finish-to-Finish
  sf('SF'); // Start-to-Finish

  final String value;
  const DependencyType(this.value);

  static DependencyType fromString(String value) {
    return DependencyType.values.firstWhere(
      (d) => d.value == value,
      orElse: () => DependencyType.fs,
    );
  }
}

/// Subscription tier
enum SubscriptionTier {
  free,
  light,
  premium;

  static SubscriptionTier fromString(String value) {
    return SubscriptionTier.values.firstWhere(
      (t) => t.name == value,
      orElse: () => SubscriptionTier.free,
    );
  }
}

/// AI setting for each feature
enum AISetting {
  auto,
  ask,
  off;

  static AISetting fromString(String value) {
    return AISetting.values.firstWhere(
      (s) => s.name == value,
      orElse: () => AISetting.auto,
    );
  }

  String get label {
    switch (this) {
      case AISetting.auto:
        return 'Auto';
      case AISetting.ask:
        return 'Manual';
      case AISetting.off:
        return 'Off';
    }
  }
}
