import 'package:equatable/equatable.dart';

/// Attachment type
enum AttachmentType {
  link,
  document,
  image;

  static AttachmentType fromString(String value) {
    switch (value) {
      case 'link':
        return AttachmentType.link;
      case 'document':
        return AttachmentType.document;
      case 'image':
        return AttachmentType.image;
      default:
        return AttachmentType.link;
    }
  }

  String toJson() => name;
}

/// Attachment model
class Attachment extends Equatable {
  final String id;
  final String taskId;
  final AttachmentType type;
  final String name;
  final String url;
  final String? mimeType;
  final int? sizeBytes;
  final String? thumbnailUrl;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const Attachment({
    required this.id,
    required this.taskId,
    required this.type,
    required this.name,
    required this.url,
    this.mimeType,
    this.sizeBytes,
    this.thumbnailUrl,
    this.metadata = const {},
    required this.createdAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      type: AttachmentType.fromString(json['type'] as String? ?? 'link'),
      name: json['name'] as String,
      url: json['url'] as String,
      mimeType: json['mime_type'] as String?,
      sizeBytes: json['size_bytes'] as int?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'type': type.toJson(),
        'name': name,
        'url': url,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'thumbnail_url': thumbnailUrl,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
      };

  /// Check if this is a link attachment
  bool get isLink => type == AttachmentType.link;

  /// Check if this is an image
  bool get isImage => type == AttachmentType.image;

  /// Check if this is a document
  bool get isDocument => type == AttachmentType.document;

  /// Get file size in human-readable format
  String get formattedSize {
    if (sizeBytes == null) return '';
    if (sizeBytes! < 1024) return '$sizeBytes B';
    if (sizeBytes! < 1024 * 1024) return '${(sizeBytes! / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Attachment copyWith({
    String? id,
    String? taskId,
    AttachmentType? type,
    String? name,
    String? url,
    String? mimeType,
    int? sizeBytes,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) {
    return Attachment(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      type: type ?? this.type,
      name: name ?? this.name,
      url: url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, taskId, type, url];
}
