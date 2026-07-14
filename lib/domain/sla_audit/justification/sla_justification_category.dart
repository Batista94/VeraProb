// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Category of reason submitted in an SLA justification (CX-05).
///
/// These categories represent the operational reasons a driver may invoke
/// to contest an infraction event detected by the Normalizer (CX-04).
///
/// Maps 1:1 to the DB CHECK constraint values in `sla_justifications`.
enum SLAJustificationCategory {
  pneuFurado,
  manutencaoUrgente,
  bloqueioPolicial,
  transitoAtipico,
  outros;

  /// DB column value stored in `sla_justifications.category`.
  String get dbValue => switch (this) {
    SLAJustificationCategory.pneuFurado => 'PNEU_FURADO',
    SLAJustificationCategory.manutencaoUrgente => 'MANUTENCAO_URGENTE',
    SLAJustificationCategory.bloqueioPolicial => 'BLOQUEIO_POLICIAL',
    SLAJustificationCategory.transitoAtipico => 'TRANSITO_ATIPICO',
    SLAJustificationCategory.outros => 'OUTROS',
  };

  /// Reconstructs from a DB value. Throws [IntegrityException] on unknown input.
  static SLAJustificationCategory fromDb(String value) {
    return switch (value) {
      'PNEU_FURADO' => SLAJustificationCategory.pneuFurado,
      'MANUTENCAO_URGENTE' => SLAJustificationCategory.manutencaoUrgente,
      'BLOQUEIO_POLICIAL' => SLAJustificationCategory.bloqueioPolicial,
      'TRANSITO_ATIPICO' => SLAJustificationCategory.transitoAtipico,
      'OUTROS' => SLAJustificationCategory.outros,
      _ => throw IntegrityException(
        'Unknown SLAJustificationCategory db value: $value',
        field: 'category',
      ),
    };
  }
}
