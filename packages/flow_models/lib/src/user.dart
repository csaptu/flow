import 'package:equatable/equatable.dart';
import 'enums.dart';

/// User model
class User extends Equatable {
  final String id;
  final String email;
  final bool emailVerified;
  final String name;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.name,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final createdAtStr = json['created_at'] as String?;
    final updatedAtStr = json['updated_at'] as String?;
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      emailVerified: json['email_verified'] as bool? ?? false,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: createdAtStr != null && createdAtStr.isNotEmpty
          ? DateTime.parse(createdAtStr)
          : DateTime.now(),
      updatedAt: updatedAtStr != null && updatedAtStr.isNotEmpty
          ? DateTime.parse(updatedAtStr)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'email_verified': emailVerified,
        'name': name,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  User copyWith({
    String? id,
    String? email,
    bool? emailVerified,
    String? name,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, email, emailVerified, name, avatarUrl];
}

/// AI preferences for user
class AIPreferences extends Equatable {
  final AISetting cleanTitle;
  final AISetting cleanDescription;
  final AISetting decompose;
  final AISetting complexityCheck;
  final AISetting smartDueDates;
  final AISetting autoGroup;
  final AISetting draftEmail;
  final AISetting draftCalendar;

  const AIPreferences({
    this.cleanTitle = AISetting.auto,
    this.cleanDescription = AISetting.auto,
    this.decompose = AISetting.ask,
    this.complexityCheck = AISetting.auto,
    this.smartDueDates = AISetting.auto,
    this.autoGroup = AISetting.ask,
    this.draftEmail = AISetting.ask,
    this.draftCalendar = AISetting.ask,
  });

  factory AIPreferences.fromJson(Map<String, dynamic> json) {
    return AIPreferences(
      cleanTitle: AISetting.fromString(json['clean_title'] ?? 'auto'),
      cleanDescription: AISetting.fromString(json['clean_description'] ?? 'auto'),
      decompose: AISetting.fromString(json['decompose'] ?? 'ask'),
      complexityCheck: AISetting.fromString(json['complexity_check'] ?? 'auto'),
      smartDueDates: AISetting.fromString(json['smart_due_dates'] ?? 'auto'),
      autoGroup: AISetting.fromString(json['auto_group'] ?? 'ask'),
      draftEmail: AISetting.fromString(json['draft_email'] ?? 'ask'),
      draftCalendar: AISetting.fromString(json['draft_calendar'] ?? 'ask'),
    );
  }

  @override
  List<Object?> get props => [
        cleanTitle,
        cleanDescription,
        decompose,
        complexityCheck,
        smartDueDates,
        autoGroup,
        draftEmail,
        draftCalendar,
      ];
}
