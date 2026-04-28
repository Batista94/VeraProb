import 'package:equatable/equatable.dart';

/// Represents a per-org HMAC secret for telemetry signing (INV-28).
///
/// Only the [secretHash] (SHA-256 of the actual secret) is stored in DB.
/// The plain-text secret is returned ONCE at generation time and never persisted.
///
/// Rotation is append-only: new version inserted, previous version gets
/// [revokedAt] timestamp.
class OrgApiSecret extends Equatable {
  final String id;
  final String organizationId;
  final String secretHash;
  final int version;
  final DateTime createdAt;
  final DateTime? rotatedAt;
  final DateTime? revokedAt;

  const OrgApiSecret({
    required this.id,
    required this.organizationId,
    required this.secretHash,
    required this.version,
    required this.createdAt,
    this.rotatedAt,
    this.revokedAt,
  });

  /// Whether this secret is currently active (not revoked).
  bool get isActive => revokedAt == null;

  factory OrgApiSecret.fromJson(Map<String, dynamic> json) {
    return OrgApiSecret(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      secretHash: json['secret_hash'] as String,
      version: json['version'] as int,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      rotatedAt: json['rotated_at'] != null
          ? DateTime.parse(json['rotated_at'] as String).toUtc()
          : null,
      revokedAt: json['revoked_at'] != null
          ? DateTime.parse(json['revoked_at'] as String).toUtc()
          : null,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    secretHash,
    version,
    createdAt,
    rotatedAt,
    revokedAt,
  ];
}
