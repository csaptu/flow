import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a client-side UUID for new entities
String generateClientId() => _uuid.v4();

/// Get device/client identifier for LWW
String getClientId() {
  // In production, this would be stored persistently per device
  // For now, use a simple approach
  return 'client_${DateTime.now().millisecondsSinceEpoch}';
}

/// Last-Write-Wins field wrapper
class LWW<T> extends Equatable {
  final T value;
  final DateTime updatedAt;
  final String updatedBy;

  const LWW({
    required this.value,
    required this.updatedAt,
    required this.updatedBy,
  });

  /// Create a new LWW field with current timestamp
  factory LWW.now(T value, String clientId) {
    return LWW(
      value: value,
      updatedAt: DateTime.now(),
      updatedBy: clientId,
    );
  }

  /// Merge two LWW fields - latest timestamp wins
  LWW<T> merge(LWW<T> other) {
    if (updatedAt.isAfter(other.updatedAt)) {
      return this;
    } else if (other.updatedAt.isAfter(updatedAt)) {
      return other;
    } else {
      // Same timestamp - use clientId as tiebreaker (deterministic)
      return updatedBy.compareTo(other.updatedBy) >= 0 ? this : other;
    }
  }

  Map<String, dynamic> toJson(dynamic Function(T) valueToJson) => {
        'value': valueToJson(value),
        'updated_at': updatedAt.toIso8601String(),
        'updated_by': updatedBy,
      };

  factory LWW.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) valueFromJson,
  ) {
    return LWW(
      value: valueFromJson(json['value']),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      updatedBy: json['updated_by'] as String,
    );
  }

  @override
  List<Object?> get props => [value, updatedAt, updatedBy];
}

/// Types of sync operations
enum SyncOperationType {
  create,
  update,
  delete,
}

/// A queued sync operation
class SyncOperation extends Equatable {
  final String id;
  final String entityId;
  final String entityType; // 'task', 'project', etc.
  final SyncOperationType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int retryCount;
  final String? error;

  const SyncOperation({
    required this.id,
    required this.entityId,
    required this.entityType,
    required this.type,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.error,
  });

  factory SyncOperation.create({
    required String entityId,
    required String entityType,
    required Map<String, dynamic> data,
  }) {
    return SyncOperation(
      id: generateClientId(),
      entityId: entityId,
      entityType: entityType,
      type: SyncOperationType.create,
      data: data,
      createdAt: DateTime.now(),
    );
  }

  factory SyncOperation.update({
    required String entityId,
    required String entityType,
    required Map<String, dynamic> data,
  }) {
    return SyncOperation(
      id: generateClientId(),
      entityId: entityId,
      entityType: entityType,
      type: SyncOperationType.update,
      data: data,
      createdAt: DateTime.now(),
    );
  }

  factory SyncOperation.delete({
    required String entityId,
    required String entityType,
  }) {
    return SyncOperation(
      id: generateClientId(),
      entityId: entityId,
      entityType: entityType,
      type: SyncOperationType.delete,
      data: const {},
      createdAt: DateTime.now(),
    );
  }

  SyncOperation copyWith({
    int? retryCount,
    String? error,
  }) {
    return SyncOperation(
      id: id,
      entityId: entityId,
      entityType: entityType,
      type: type,
      data: data,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      error: error,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_id': entityId,
        'entity_type': entityType,
        'type': type.name,
        'data': data,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
        'error': error,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String,
      entityId: json['entity_id'] as String,
      entityType: json['entity_type'] as String,
      type: SyncOperationType.values.byName(json['type'] as String),
      data: json['data'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['created_at'] as String),
      retryCount: json['retry_count'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, entityId, entityType, type, createdAt];
}

/// Sync status for the app
enum SyncStatus {
  synced,      // All changes synced
  syncing,     // Currently syncing
  pending,     // Has pending changes
  offline,     // No network connection
  error,       // Sync failed
}

/// Overall sync state
class SyncState extends Equatable {
  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? error;

  const SyncState({
    this.status = SyncStatus.synced,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.error,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? error,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, pendingCount, lastSyncAt, error];
}
