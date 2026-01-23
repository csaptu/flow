import 'package:equatable/equatable.dart';

/// User AI Profile - stores personalized context for AI interactions
class UserAIProfile extends Equatable {
  final String userId;

  // Editable fields (admin can modify)
  final String? identitySummary;
  final String? communicationStyle;
  final String? workContext;
  final String? personalContext;
  final String? socialGraph;
  final String? locationsContext;
  final String? routinePatterns;
  final String? taskStylePreferences;
  final String? goalsAndPriorities;

  // Auto-generated fields (refreshed by AI)
  final String? recentActivitySummary;
  final String? currentFocus;
  final String? upcomingCommitments;

  // Refresh metadata
  final DateTime lastRefreshedAt;
  final String? refreshTrigger;
  final int tasksSinceRefresh;

  final DateTime createdAt;
  final DateTime updatedAt;

  const UserAIProfile({
    required this.userId,
    this.identitySummary,
    this.communicationStyle,
    this.workContext,
    this.personalContext,
    this.socialGraph,
    this.locationsContext,
    this.routinePatterns,
    this.taskStylePreferences,
    this.goalsAndPriorities,
    this.recentActivitySummary,
    this.currentFocus,
    this.upcomingCommitments,
    required this.lastRefreshedAt,
    this.refreshTrigger,
    required this.tasksSinceRefresh,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserAIProfile.fromJson(Map<String, dynamic> json) {
    return UserAIProfile(
      userId: json['user_id'] as String,
      identitySummary: json['identity_summary'] as String?,
      communicationStyle: json['communication_style'] as String?,
      workContext: json['work_context'] as String?,
      personalContext: json['personal_context'] as String?,
      socialGraph: json['social_graph'] as String?,
      locationsContext: json['locations_context'] as String?,
      routinePatterns: json['routine_patterns'] as String?,
      taskStylePreferences: json['task_style_preferences'] as String?,
      goalsAndPriorities: json['goals_and_priorities'] as String?,
      recentActivitySummary: json['recent_activity_summary'] as String?,
      currentFocus: json['current_focus'] as String?,
      upcomingCommitments: json['upcoming_commitments'] as String?,
      lastRefreshedAt: DateTime.parse(json['last_refreshed_at'] as String),
      refreshTrigger: json['refresh_trigger'] as String?,
      tasksSinceRefresh: json['tasks_since_refresh'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'identity_summary': identitySummary,
      'communication_style': communicationStyle,
      'work_context': workContext,
      'personal_context': personalContext,
      'social_graph': socialGraph,
      'locations_context': locationsContext,
      'routine_patterns': routinePatterns,
      'task_style_preferences': taskStylePreferences,
      'goals_and_priorities': goalsAndPriorities,
      'recent_activity_summary': recentActivitySummary,
      'current_focus': currentFocus,
      'upcoming_commitments': upcomingCommitments,
      'last_refreshed_at': lastRefreshedAt.toIso8601String(),
      'refresh_trigger': refreshTrigger,
      'tasks_since_refresh': tasksSinceRefresh,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserAIProfile copyWith({
    String? userId,
    String? identitySummary,
    String? communicationStyle,
    String? workContext,
    String? personalContext,
    String? socialGraph,
    String? locationsContext,
    String? routinePatterns,
    String? taskStylePreferences,
    String? goalsAndPriorities,
    String? recentActivitySummary,
    String? currentFocus,
    String? upcomingCommitments,
    DateTime? lastRefreshedAt,
    String? refreshTrigger,
    int? tasksSinceRefresh,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserAIProfile(
      userId: userId ?? this.userId,
      identitySummary: identitySummary ?? this.identitySummary,
      communicationStyle: communicationStyle ?? this.communicationStyle,
      workContext: workContext ?? this.workContext,
      personalContext: personalContext ?? this.personalContext,
      socialGraph: socialGraph ?? this.socialGraph,
      locationsContext: locationsContext ?? this.locationsContext,
      routinePatterns: routinePatterns ?? this.routinePatterns,
      taskStylePreferences: taskStylePreferences ?? this.taskStylePreferences,
      goalsAndPriorities: goalsAndPriorities ?? this.goalsAndPriorities,
      recentActivitySummary: recentActivitySummary ?? this.recentActivitySummary,
      currentFocus: currentFocus ?? this.currentFocus,
      upcomingCommitments: upcomingCommitments ?? this.upcomingCommitments,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      refreshTrigger: refreshTrigger ?? this.refreshTrigger,
      tasksSinceRefresh: tasksSinceRefresh ?? this.tasksSinceRefresh,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if profile has any content
  bool get isEmpty =>
      identitySummary == null &&
      communicationStyle == null &&
      workContext == null &&
      personalContext == null &&
      socialGraph == null &&
      locationsContext == null &&
      routinePatterns == null &&
      taskStylePreferences == null &&
      goalsAndPriorities == null &&
      recentActivitySummary == null &&
      currentFocus == null &&
      upcomingCommitments == null;

  @override
  List<Object?> get props => [
        userId,
        identitySummary,
        communicationStyle,
        workContext,
        personalContext,
        socialGraph,
        locationsContext,
        routinePatterns,
        taskStylePreferences,
        goalsAndPriorities,
        recentActivitySummary,
        currentFocus,
        upcomingCommitments,
        lastRefreshedAt,
        refreshTrigger,
        tasksSinceRefresh,
      ];
}

/// Metadata for profile fields
class ProfileFieldMeta {
  final String key;
  final String label;
  final String description;
  final int maxLength;
  final bool isAutoGenerated;

  const ProfileFieldMeta({
    required this.key,
    required this.label,
    required this.description,
    this.maxLength = 500,
    this.isAutoGenerated = false,
  });

  static const List<ProfileFieldMeta> editableFields = [
    ProfileFieldMeta(
      key: 'identity_summary',
      label: 'Identity',
      description: 'Who you are - role, background',
      maxLength: 200,
    ),
    ProfileFieldMeta(
      key: 'communication_style',
      label: 'Communication Style',
      description: 'Tone, verbosity, formality preferences',
      maxLength: 200,
    ),
    ProfileFieldMeta(
      key: 'work_context',
      label: 'Work Context',
      description: 'Job, projects, responsibilities',
      maxLength: 300,
    ),
    ProfileFieldMeta(
      key: 'personal_context',
      label: 'Personal Life',
      description: 'Family, hobbies, personal interests',
      maxLength: 200,
    ),
    ProfileFieldMeta(
      key: 'social_graph',
      label: 'Key People',
      description: 'Important people mentioned in tasks',
      maxLength: 300,
    ),
    ProfileFieldMeta(
      key: 'locations_context',
      label: 'Locations',
      description: 'Frequent places mentioned',
      maxLength: 200,
    ),
    ProfileFieldMeta(
      key: 'routine_patterns',
      label: 'Routines',
      description: 'Daily/weekly patterns observed',
      maxLength: 200,
    ),
    ProfileFieldMeta(
      key: 'task_style_preferences',
      label: 'Task Preferences',
      description: 'How you like tasks structured',
      maxLength: 200,
    ),
    ProfileFieldMeta(
      key: 'goals_and_priorities',
      label: 'Goals',
      description: 'Stated or implied goals',
      maxLength: 300,
    ),
  ];

  static const List<ProfileFieldMeta> autoFields = [
    ProfileFieldMeta(
      key: 'recent_activity_summary',
      label: 'Recent Activity',
      description: 'Summary of last 7 days activity',
      maxLength: 300,
      isAutoGenerated: true,
    ),
    ProfileFieldMeta(
      key: 'current_focus',
      label: 'Current Focus',
      description: 'What you seem focused on currently',
      maxLength: 200,
      isAutoGenerated: true,
    ),
    ProfileFieldMeta(
      key: 'upcoming_commitments',
      label: 'Upcoming',
      description: 'Near-term deadlines or events',
      maxLength: 200,
      isAutoGenerated: true,
    ),
  ];

  static const List<ProfileFieldMeta> allFields = [
    ...editableFields,
    ...autoFields,
  ];

  /// Get field value from a profile
  static String? getFieldValue(UserAIProfile profile, String key) {
    switch (key) {
      case 'identity_summary':
        return profile.identitySummary;
      case 'communication_style':
        return profile.communicationStyle;
      case 'work_context':
        return profile.workContext;
      case 'personal_context':
        return profile.personalContext;
      case 'social_graph':
        return profile.socialGraph;
      case 'locations_context':
        return profile.locationsContext;
      case 'routine_patterns':
        return profile.routinePatterns;
      case 'task_style_preferences':
        return profile.taskStylePreferences;
      case 'goals_and_priorities':
        return profile.goalsAndPriorities;
      case 'recent_activity_summary':
        return profile.recentActivitySummary;
      case 'current_focus':
        return profile.currentFocus;
      case 'upcoming_commitments':
        return profile.upcomingCommitments;
      default:
        return null;
    }
  }
}
