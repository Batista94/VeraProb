import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Domain-layer exception for optimistic locking conflicts (Lost Update prevention).
///
/// Thrown when a write operation targets a resource with a stale version number,
/// indicating that another concurrent modification has already been applied.
///
/// **Why a separate exception (not [IntegrityException])?**
/// - `IntegrityException` signals data corruption or constraint violations.
/// - `ConflictException` signals a **recoverable concurrency conflict** — the
///   client can retry after refreshing the entity state.
///
/// **Forensic Discrimination (Lead Reviewer Gate):**
/// When `maybeSingle()` returns null after a versioned update, the repository
/// must distinguish between:
///   1. **Version mismatch**: the resource exists but at a newer version → [ConflictException]
///   2. **Resource deleted**: the resource no longer exists → [ResourceNotFoundException]
///
/// This exception carries sufficient metadata for the UI to suggest the
/// correct recovery action ("Refresh" vs "Resource no longer exists").
///
/// **INV-10 (Error Visibility):** Fail-Fast — never silently ignore stale writes.
/// **INV-26 (Error Parity):** Never leak PostgREST codes; this exception is the
///   sanitized domain-layer signal for 409 Conflict responses.
class ConflictException extends IntegrityException {
  /// Domain name of the conflicted resource (e.g., 'contract', 'vehicle').
  final String resourceType;

  /// UUID or identifier of the conflicted resource.
  final String resourceId;

  /// The version number the client attempted to write.
  final int clientVersion;

  /// The version number currently stored in the database (if known).
  /// Null if the resource no longer exists (deleted by another user).
  final int? currentVersion;

  const ConflictException({
    required this.resourceType,
    required this.resourceId,
    required this.clientVersion,
    this.currentVersion,
  }) : super(
         'Optimistic lock conflict on $resourceType "$resourceId": '
         'client sent version $clientVersion, '
         '${currentVersion != null ? 'current version is $currentVersion' : 'resource no longer exists'}',
       );

  /// Constructor for the case where the resource was deleted concurrently.
  const ConflictException.deleted({
    required String resourceType,
    required String resourceId,
    required int clientVersion,
  }) : this(
         resourceType: resourceType,
         resourceId: resourceId,
         clientVersion: clientVersion,
         currentVersion: null,
       );

  /// Constructor for the case where the resource exists but at a newer version.
  const ConflictException.staleVersion({
    required String resourceType,
    required String resourceId,
    required int clientVersion,
    required int currentVersion,
  }) : this(
         resourceType: resourceType,
         resourceId: resourceId,
         clientVersion: clientVersion,
         currentVersion: currentVersion,
       );

  /// Returns true if the resource was deleted concurrently.
  bool get isDeleted => currentVersion == null;

  /// Returns true if this is a pure version mismatch (resource still exists).
  bool get isVersionMismatch => currentVersion != null;

  @override
  String toString() =>
      'ConflictException: $message${isDeleted ? ' [DELETED]' : ' [STALE v$currentVersion]'}';
}
