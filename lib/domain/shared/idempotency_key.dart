import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Value object representing an idempotency key entry.
///
/// Idempotency keys ensure that duplicate requests (double-clicks, network
/// retries, infrastructure failures) never produce duplicate side-effects.
///
/// **Lifecycle:**
/// 1. Client generates a unique key (UUID v4 or deterministic hash).
/// 2. Server registers key as 'processing' BEFORE business logic.
/// 3. Business logic executes.
/// 4. Key is updated to 'completed' with the response body.
/// 5. On duplicate request, step 2 returns the cached response (short-circuit).
///
/// **INV-33:** All mutating operations MUST carry an idempotency key.
/// The key is checked before any business logic executes.
class IdempotencyKey {
  /// Unique identifier for this idempotency key (client-generated).
  final String id;

  /// User who initiated the command (for per-user idempotency scoping).
  final String userId;

  /// The command path being idempotent (e.g., 'close_contract').
  final String commandPath;

  /// Organization context (INV-1: tenant isolation).
  final String organizationId;

  /// Current status: 'processing', 'completed', or 'error'.
  final String status;

  /// HTTP-like response code (e.g., 200, 404, 500).
  /// Null while status is 'processing'.
  final int? responseCode;

  /// Canonical JSON snapshot of the command response.
  /// Includes updated entity version for optimistic locking replay.
  /// Null while status is 'processing'.
  final Map<String, dynamic>? responseBody;

  /// When this key was created (UTC).
  final DateTime createdAtUtc;

  /// When this key completed (UTC). Null while processing.
  final DateTime? completedAtUtc;

  /// Maximum time (in minutes) before a 'processing' key is considered stale
  /// and eligible for reclamation by a retry.
  ///
  /// **Default: 5 minutes** — suitable for lightweight admin commands.
  /// **Override:** Heavy batch commands (e.g., monthly audit processing)
  /// should set a higher value (e.g., 30 or 60 minutes) to prevent premature
  /// reclamation while the original request is still legitimately running.
  final int staleThresholdMinutes;

  const IdempotencyKey({
    required this.id,
    required this.userId,
    required this.commandPath,
    required this.organizationId,
    required this.status,
    this.responseCode,
    this.responseBody,
    required this.createdAtUtc,
    this.completedAtUtc,
    this.staleThresholdMinutes = 5,
  });

  /// Creates a new idempotency key in 'processing' state.
  ///
  /// [staleThresholdMinutes] controls how long a 'processing' key must wait
  /// before a retry can reclaim it. Default is 5 minutes (lightweight commands).
  /// Set to 30+ for heavy batch operations that may legitimately take longer.
  factory IdempotencyKey.processing({
    required String id,
    required String userId,
    required String commandPath,
    required String organizationId,
    required DateTime nowUtc,
    int staleThresholdMinutes = 5,
  }) {
    return IdempotencyKey(
      id: id,
      userId: userId,
      commandPath: commandPath,
      organizationId: organizationId,
      status: 'processing',
      createdAtUtc: nowUtc,
      staleThresholdMinutes: staleThresholdMinutes,
    );
  }

  /// Creates a new idempotency key whose [id] is a SHA-256 hex digest of the
  /// canonical content: `userId|commandPath|organizationId|sortedJsonPayload`.
  ///
  /// **INV-11 — Content-Based Addressing:** The [id] is deterministic and
  /// derived purely from the payload. [nowUtc] is metadata only — it does NOT
  /// influence the hash.
  factory IdempotencyKey.fromPayload({
    required String userId,
    required String commandPath,
    required String organizationId,
    required Map<String, dynamic> payload,
    required DateTime nowUtc,
    int staleThresholdMinutes = 5,
  }) {
    final canonical =
        '$userId|$commandPath|$organizationId|${jsonEncode(_sortedMap(payload))}';
    final id = sha256.convert(utf8.encode(canonical)).toString();
    return IdempotencyKey.processing(
      id: id,
      userId: userId,
      commandPath: commandPath,
      organizationId: organizationId,
      nowUtc: nowUtc,
      staleThresholdMinutes: staleThresholdMinutes,
    );
  }

  /// Recursively sorts map keys so that `jsonEncode` output is canonical
  /// regardless of insertion order.
  static Map<String, dynamic> _sortedMap(Map<String, dynamic> map) {
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(
      sorted.map(
        (e) => MapEntry(
          e.key,
          e.value is Map<String, dynamic>
              ? _sortedMap(e.value as Map<String, dynamic>)
              : e.value,
        ),
      ),
    );
  }

  /// Returns a copy of this key with 'completed' status and response data.
  IdempotencyKey complete({
    required int responseCode,
    required Map<String, dynamic> responseBody,
    required DateTime nowUtc,
  }) {
    return IdempotencyKey(
      id: id,
      userId: userId,
      commandPath: commandPath,
      organizationId: organizationId,
      status: 'completed',
      responseCode: responseCode,
      responseBody: responseBody,
      createdAtUtc: createdAtUtc,
      completedAtUtc: nowUtc,
      staleThresholdMinutes: staleThresholdMinutes,
    );
  }

  /// Returns a copy of this key with 'error' status.
  IdempotencyKey fail({required int responseCode, required DateTime nowUtc}) {
    return IdempotencyKey(
      id: id,
      userId: userId,
      commandPath: commandPath,
      organizationId: organizationId,
      status: 'error',
      responseCode: responseCode,
      createdAtUtc: createdAtUtc,
      completedAtUtc: nowUtc,
      staleThresholdMinutes: staleThresholdMinutes,
    );
  }

  /// Whether this key has been completed successfully.
  bool get isCompleted => status == 'completed';

  /// Whether this key is currently being processed.
  bool get isProcessing => status == 'processing';

  /// Whether this key resulted in an error.
  bool get isError => status == 'error';

  @override
  String toString() =>
      'IdempotencyKey(id: $id, status: $status, command: $commandPath)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdempotencyKey &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId;

  @override
  int get hashCode => id.hashCode ^ userId.hashCode;
}
