import 'package:veraprob/domain/admin/org_api_secret.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';

/// Repository interface for Organization aggregate operations.
///
/// INV-8: All read/write ops enforce organization_id isolation.
abstract class OrganizationRepository {
  /// Find a single organization by ID.
  Future<Organization?> findById(String id);

  /// Update organization fields.
  Future<void> update(Organization organization);

  /// List all organizations, optionally filtered by [status].
  Future<List<Organization>> findAll({OrgStatus? status});

  /// Update organization status with audit trail.
  /// Returns the updated organization.
  Future<void> updateStatus(
    String orgId,
    OrgStatus status,
    String reason,
    String actorId,
    String actorType,
  );

  /// Find the active API secret for an organization (INV-28).
  Future<OrgApiSecret?> findApiSecret(String orgId);
}
