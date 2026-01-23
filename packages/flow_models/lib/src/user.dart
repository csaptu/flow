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

/// AI preferences for user - matches all features in the plan document
class AIPreferences extends Equatable {
  // Free tier features
  final AISetting cleanTitle;
  final AISetting cleanDescription;

  // Light tier features
  final AISetting decompose;
  final AISetting entityExtraction;
  final AISetting duplicateCheck;
  final AISetting recurringDetection;

  // Premium tier features
  final AISetting sendEmail;
  final AISetting sendCalendar;

  const AIPreferences({
    // Free - Auto by default
    this.cleanTitle = AISetting.auto,
    this.cleanDescription = AISetting.auto,
    // Light - Mixed defaults
    this.decompose = AISetting.ask,
    this.entityExtraction = AISetting.auto,
    this.duplicateCheck = AISetting.ask,
    this.recurringDetection = AISetting.ask,
    // Premium - Ask by default
    this.sendEmail = AISetting.ask,
    this.sendCalendar = AISetting.ask,
  });

  /// Create with all defaults
  factory AIPreferences.defaults() => const AIPreferences();

  factory AIPreferences.fromJson(Map<String, dynamic> json) {
    return AIPreferences(
      cleanTitle: AISetting.fromString(json['clean_title'] ?? 'auto'),
      cleanDescription: AISetting.fromString(json['clean_description'] ?? 'auto'),
      decompose: AISetting.fromString(json['decompose'] ?? 'ask'),
      entityExtraction: AISetting.fromString(json['entity_extraction'] ?? 'auto'),
      duplicateCheck: AISetting.fromString(json['duplicate_check'] ?? 'ask'),
      recurringDetection: AISetting.fromString(json['recurring_detection'] ?? 'ask'),
      sendEmail: AISetting.fromString(json['send_email'] ?? 'ask'),
      sendCalendar: AISetting.fromString(json['send_calendar'] ?? 'ask'),
    );
  }

  Map<String, dynamic> toJson() => {
        'clean_title': cleanTitle.name,
        'clean_description': cleanDescription.name,
        'decompose': decompose.name,
        'entity_extraction': entityExtraction.name,
        'duplicate_check': duplicateCheck.name,
        'recurring_detection': recurringDetection.name,
        'send_email': sendEmail.name,
        'send_calendar': sendCalendar.name,
      };

  /// Get setting for an AIFeature
  AISetting getSetting(dynamic feature) {
    // feature can be AIFeature enum from ai.dart
    final key = feature.key as String;
    switch (key) {
      case 'clean_title':
        return cleanTitle;
      case 'clean_description':
        return cleanDescription;
      case 'decompose':
        return decompose;
      case 'entity_extraction':
        return entityExtraction;
      case 'duplicate_check':
        return duplicateCheck;
      case 'recurring_detection':
        return recurringDetection;
      case 'send_email':
        return sendEmail;
      case 'send_calendar':
        return sendCalendar;
      default:
        return AISetting.ask;
    }
  }

  /// Create a copy with an updated setting for a feature
  AIPreferences copyWithFeature({required dynamic feature, required AISetting setting}) {
    final key = feature.key as String;
    return AIPreferences(
      cleanTitle: key == 'clean_title' ? setting : cleanTitle,
      cleanDescription: key == 'clean_description' ? setting : cleanDescription,
      decompose: key == 'decompose' ? setting : decompose,
      entityExtraction: key == 'entity_extraction' ? setting : entityExtraction,
      duplicateCheck: key == 'duplicate_check' ? setting : duplicateCheck,
      recurringDetection: key == 'recurring_detection' ? setting : recurringDetection,
      sendEmail: key == 'send_email' ? setting : sendEmail,
      sendCalendar: key == 'send_calendar' ? setting : sendCalendar,
    );
  }

  @override
  List<Object?> get props => [
        cleanTitle,
        cleanDescription,
        decompose,
        entityExtraction,
        duplicateCheck,
        recurringDetection,
        sendEmail,
        sendCalendar,
      ];
}
