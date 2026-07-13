// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Category of reason submitted in a contractor justification.
///
/// Maps 1:1 to the DB CHECK constraint values in `contractor_justifications`.
enum JustificationCategory {
  mechanical,
  forceMajeure,
  traffic,
  routeDeviation,
  communication,
  other;

  /// DB column value stored in `contractor_justifications.category`.
  String get dbValue => switch (this) {
    JustificationCategory.mechanical => 'MECHANICAL',
    JustificationCategory.forceMajeure => 'FORCE_MAJEURE',
    JustificationCategory.traffic => 'TRAFFIC',
    JustificationCategory.routeDeviation => 'ROUTE_DEVIATION',
    JustificationCategory.communication => 'COMMUNICATION',
    JustificationCategory.other => 'OTHER',
  };

  /// Reconstructs from a DB value. Throws [IntegrityException] on unknown input.
  static JustificationCategory fromDb(String value) {
    return switch (value) {
      'MECHANICAL' => JustificationCategory.mechanical,
      'FORCE_MAJEURE' => JustificationCategory.forceMajeure,
      'TRAFFIC' => JustificationCategory.traffic,
      'ROUTE_DEVIATION' => JustificationCategory.routeDeviation,
      'COMMUNICATION' => JustificationCategory.communication,
      'OTHER' => JustificationCategory.other,
      _ => throw IntegrityException(
        'Unknown JustificationCategory db value: $value',
        field: 'category',
      ),
    };
  }
}
