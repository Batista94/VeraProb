import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// How a sanction acknowledgement ("De Acordo") was captured.
///
/// [portalToken] — the carrier accepted through the tokenized portal; bound to
/// the exact snapshot hash the system served (INV-9).
/// [internalRecord] — an off-band acceptance (email/phone) recorded by a
/// TENANT_ADMIN; no hash.
enum AcknowledgementMethod { portalToken, internalRecord }

/// Entity: a forensic record of formal penalty acceptance (Sprint A, M4).
///
/// Append-only at the DB level (`sanction_acknowledgements`). Equality covers
/// all structural fields so a hash-swap cannot masquerade as the same record.
class SanctionAcknowledgement extends Equatable {
  final String id;
  final String organizationId;
  final String queueEntryId;

  /// The exact served snapshot hash the carrier acknowledged (64-char hex).
  /// Null for [AcknowledgementMethod.internalRecord].
  final String? snapshotHashAcknowledged;

  final AcknowledgementMethod method;

  /// Portal token used for a [AcknowledgementMethod.portalToken] acceptance.
  final String? acknowledgedViaTokenId;

  /// User who recorded an [AcknowledgementMethod.internalRecord] acceptance.
  final String? acknowledgedByUserId;

  final String? notes;
  final DateTime acknowledgedAtUtc;

  const SanctionAcknowledgement({
    required this.id,
    required this.organizationId,
    required this.queueEntryId,
    required this.snapshotHashAcknowledged,
    required this.method,
    required this.acknowledgedViaTokenId,
    required this.acknowledgedByUserId,
    required this.notes,
    required this.acknowledgedAtUtc,
  });

  /// Validates the two legal shapes (mirrors `chk_sack_method_consistency`).
  factory SanctionAcknowledgement.validated({
    required String id,
    required String organizationId,
    required String queueEntryId,
    required String? snapshotHashAcknowledged,
    required AcknowledgementMethod method,
    required String? acknowledgedViaTokenId,
    required String? acknowledgedByUserId,
    required String? notes,
    required DateTime acknowledgedAtUtc,
  }) {
    if (!acknowledgedAtUtc.isUtc) {
      throw const IntegrityException('acknowledgedAtUtc must be UTC (INV-6).');
    }
    if (snapshotHashAcknowledged != null &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(snapshotHashAcknowledged)) {
      throw const IntegrityException('snapshot hash format invalid (INV-9).');
    }
    switch (method) {
      case AcknowledgementMethod.portalToken:
        if (snapshotHashAcknowledged == null ||
            acknowledgedViaTokenId == null) {
          throw const IntegrityException(
            'PORTAL_TOKEN acknowledgement requires snapshot hash + token id.',
          );
        }
      case AcknowledgementMethod.internalRecord:
        if (acknowledgedByUserId == null) {
          throw const IntegrityException(
            'INTERNAL_RECORD acknowledgement requires an acknowledging user.',
          );
        }
    }
    return SanctionAcknowledgement(
      id: id,
      organizationId: organizationId,
      queueEntryId: queueEntryId,
      snapshotHashAcknowledged: snapshotHashAcknowledged,
      method: method,
      acknowledgedViaTokenId: acknowledgedViaTokenId,
      acknowledgedByUserId: acknowledgedByUserId,
      notes: notes,
      acknowledgedAtUtc: acknowledgedAtUtc,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    queueEntryId,
    snapshotHashAcknowledged,
    method,
    acknowledgedViaTokenId,
    acknowledgedByUserId,
    notes,
    acknowledgedAtUtc,
  ];
}

/// DB ⇄ domain mapping for [AcknowledgementMethod].
extension AcknowledgementMethodDb on AcknowledgementMethod {
  String get dbValue => switch (this) {
    AcknowledgementMethod.portalToken => 'PORTAL_TOKEN',
    AcknowledgementMethod.internalRecord => 'INTERNAL_RECORD',
  };

  static AcknowledgementMethod fromDbValue(String value) => switch (value) {
    'PORTAL_TOKEN' => AcknowledgementMethod.portalToken,
    'INTERNAL_RECORD' => AcknowledgementMethod.internalRecord,
    _ => throw IntegrityException('Unknown acknowledgement method: $value'),
  };
}
