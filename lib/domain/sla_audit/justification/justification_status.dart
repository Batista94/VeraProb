// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Review status of a contractor justification.
///
/// Maps 1:1 to the DB CHECK constraint values in `contractor_justifications`.
enum JustificationStatus {
  pending,
  approved,
  rejected,
  expired;

  /// DB column value stored in `contractor_justifications.status`.
  String get dbValue => switch (this) {
    JustificationStatus.pending => 'PENDING',
    JustificationStatus.approved => 'APPROVED',
    JustificationStatus.rejected => 'REJECTED',
    JustificationStatus.expired => 'EXPIRED',
  };

  /// Reconstructs from a DB value. Throws [IntegrityException] on unknown input.
  static JustificationStatus fromDb(String value) {
    return switch (value) {
      'PENDING' => JustificationStatus.pending,
      'APPROVED' => JustificationStatus.approved,
      'REJECTED' => JustificationStatus.rejected,
      'EXPIRED' => JustificationStatus.expired,
      _ => throw IntegrityException(
        'Unknown JustificationStatus db value: $value',
        field: 'status',
      ),
    };
  }
}
