import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

/// Application-layer service for tenant isolation validation.
///
/// Enforces:
/// - **INV-1 (Identity Sovereignty):** Fail-Fast check that the
///   `organization_id` in the request payload matches the JWT claim.
/// - **INV-27 (Origin Ownership):** Verifies that a source resource
///   belongs to the requesting organization before any operation.
///
/// Both violations throw domain exceptions that are later mapped to
/// identical HTTP 404 responses by [SovereigntyErrorMapper] (INV-26).
class TenantValidationService {
  final IAuthRepository _authRepository;

  TenantValidationService({required IAuthRepository authRepository})
    : _authRepository = authRepository;

  /// Validates that the `organization_id` in the payload matches the
  /// authenticated user's JWT `organization_id` claim (INV-1: Fail-Fast).
  ///
  /// **Use Case:** Edge Functions and handlers MUST call this before
  /// processing any request that carries an `org_id` in the body.
  ///
  /// Throws [SovereigntyViolationException] if:
  /// - The session is invalid/expired (no authenticated user).
  /// - The `payloadOrgId` differs from the JWT's `org_id`.
  Future<void> assertTenantMatches({
    required String payloadOrgId,
    required String sessionId,
  }) async {
    final user = await _authRepository.getUserBySessionId(sessionId);

    // No active session or user lacks org_id → sovereignty violation
    if (user == null) {
      throw SovereigntyViolationException(
        payloadOrgId: payloadOrgId,
        jwtOrgId: 'none',
      );
    }

    // Payload org_id must EXACTLY match the JWT claim (case-sensitive)
    if (payloadOrgId != user.tenantId) {
      throw SovereigntyViolationException(
        payloadOrgId: payloadOrgId,
        jwtOrgId: user.tenantId,
      );
    }
  }

  /// Verifies that a source resource belongs to the requesting organization
  /// before executing source-to-destination operations (INV-27: Origin
  /// Ownership).
  ///
  /// **Use Case:** Clone, transfer, or reference operations where the
  /// caller provides a `resourceOrgId` (extracted from the resource's
  /// DB row) and a `requesterOrgId` (extracted from the JWT).
  ///
  /// **Important:** The `resourceOrgId` should come from a prior DB lookup
  /// that already filtered by `organization_id`. If the resource was not
  /// found, the caller should also throw [ResourceNotFoundException].
  ///
  /// Throws [ResourceNotFoundException] if the resource's organization
  /// does not match the requester's organization (treated as "not found"
  /// to prevent Oracle Attacks — INV-26).
  void verifySourceOwnership({
    required String resourceOrgId,
    required String requesterOrgId,
    String? resourceType,
    String? resourceId,
  }) {
    if (resourceOrgId != requesterOrgId) {
      throw ResourceNotFoundException(
        resourceType: resourceType,
        resourceId: resourceId,
      );
    }
  }
}
