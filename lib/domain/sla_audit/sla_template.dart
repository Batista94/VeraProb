import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

import 'domain_exception.dart';
import 'sla_penalties.dart';
import 'transport_vertical.dart';

/// Core Domain Entity representing a named preset of [SLAPenalties].
///
/// SLA Templates allow operators to configure penalty parameters once and
/// reuse them across multiple plan declarations â€” eliminating repetitive
/// manual entry in the Wizard Step 3.
///
/// **Classification:** Core Domain Entity.
/// [SLAPenalties] remains a pure domain Value Object with no knowledge of
/// templates. A template is purely a named JSONB preset.
///
/// **Immutability:** All fields are final. Editing a template creates a new
/// record (not enforced here â€” left to the UI/handler layer).
///
/// Equality is based exclusively on [id].
class SlaTemplate extends Equatable {
  final String id;
  final String organizationId;
  final String name;
  final String? description;
  final TransportVertical? vertical;
  final SLAPenalties penalties;
  final DateTime createdAt;

  const SlaTemplate._({
    required this.id,
    required this.organizationId,
    required this.name,
    this.description,
    this.vertical,
    required this.penalties,
    required this.createdAt,
  });

  /// Creates a new [SlaTemplate] with a generated UUID and validated fields.
  ///
  /// Throws [DomainException] if [name] is empty or [organizationId] is empty.
  static SlaTemplate create({
    required String organizationId,
    required String name,
    String? description,
    TransportVertical? vertical,
    required SLAPenalties penalties,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (name.trim().isEmpty) {
      throw const DomainException('Template name must not be empty');
    }
    if (name.length > 100) {
      throw const DomainException(
        'Template name must not exceed 100 characters',
      );
    }

    return SlaTemplate._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      name: name,
      description: description,
      vertical: vertical,
      penalties: penalties,
      createdAt:
          StaticDateTimeProvider.instance?.nowUtc() ?? DateTime.now().toUtc(),
    );
  }

  /// Reconstitutes from persistence without re-validating invariants.
  static SlaTemplate reconstitute({
    required String id,
    required String organizationId,
    required String name,
    String? description,
    TransportVertical? vertical,
    required SLAPenalties penalties,
    required DateTime createdAt,
  }) {
    return SlaTemplate._(
      id: id,
      organizationId: organizationId,
      name: name,
      description: description,
      vertical: vertical,
      penalties: penalties,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id];
}
