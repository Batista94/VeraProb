import 'package:veraprob/domain/admin/org_api_secret.dart';

/// Application-layer projection of [OrgApiSecret] for the presentation layer.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// All fields are primitives (`String`, `int`, `DateTime`). The widget
/// [OrgSecretCard] accepts this ViewModel instead of the domain entity,
/// so [OrgApiSecret] is never imported in `lib/features/`.
///
/// The plain-text secret (returned once at generation time) is NOT a field
/// here — it is returned directly as a [String] from the handler result and
/// stored as widget-local state, never persisted.
class OrgApiSecretViewModel {
  final String id;
  final String organizationId;

  /// SHA-256 hash of the actual secret — never the plain-text value.
  final String secretHash;

  final int version;
  final DateTime createdAt;
  final DateTime? rotatedAt;
  final DateTime? revokedAt;

  /// Whether this secret is currently active (not revoked).
  final bool isActive;

  const OrgApiSecretViewModel({
    required this.id,
    required this.organizationId,
    required this.secretHash,
    required this.version,
    required this.createdAt,
    this.rotatedAt,
    this.revokedAt,
    required this.isActive,
  });

  /// Creates a ViewModel from the domain entity.
  /// Called exclusively from application-layer factories.
  factory OrgApiSecretViewModel.fromDomain(OrgApiSecret domain) {
    return OrgApiSecretViewModel(
      id: domain.id,
      organizationId: domain.organizationId,
      secretHash: domain.secretHash,
      version: domain.version,
      createdAt: domain.createdAt,
      rotatedAt: domain.rotatedAt,
      revokedAt: domain.revokedAt,
      isActive: domain.isActive,
    );
  }
}
