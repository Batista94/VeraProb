/// Review status of a contractor justification.
///
/// Maps 1:1 to the DB CHECK constraint values in `contractor_justifications`.
enum JustificationStatus {
  pending,
  approved,
  rejected;

  /// DB column value stored in `contractor_justifications.status`.
  String get dbValue => switch (this) {
    JustificationStatus.pending => 'PENDING',
    JustificationStatus.approved => 'APPROVED',
    JustificationStatus.rejected => 'REJECTED',
  };

  /// Reconstructs from a DB value. Throws [ArgumentError] on unknown input.
  static JustificationStatus fromDb(String value) {
    return switch (value) {
      'PENDING' => JustificationStatus.pending,
      'APPROVED' => JustificationStatus.approved,
      'REJECTED' => JustificationStatus.rejected,
      _ => throw ArgumentError('Unknown JustificationStatus db value: $value'),
    };
  }
}
