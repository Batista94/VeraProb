import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'domain_exception.dart';
import 'sla_penalties.dart';
import 'transport_vertical.dart';

/// Domain entity representing a service definition within a contract.
///
/// A ServiceManifest decouples "what service is being provided" (vertical,
/// penalty config, SLA terms) from "which assets are assigned" (vehicles,
/// drivers). This allows contracts to define multiple service obligations
/// independently of fleet assignment.
///
/// **Immutability:** All fields are final. Equality is based on [id].
/// **INV-18:** Pure Dart â€” no infrastructure dependencies.
class ServiceManifest extends Equatable {
  final String id;
  final String organizationId;
  final String contractId;
  final String name;
  final String? description;
  final String? slaTemplateId;
  final TransportVertical vertical;
  final SLAPenalties penalties;
  final DateTime createdAtUtc;

  const ServiceManifest._({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.name,
    this.description,
    this.slaTemplateId,
    required this.vertical,
    required this.penalties,
    required this.createdAtUtc,
  });

  /// Creates a new [ServiceManifest] with a generated UUID and validated fields.
  ///
  /// Throws [DomainException] if required fields are empty.
  static ServiceManifest create({
    required String organizationId,
    required String contractId,
    required String name,
    String? description,
    String? slaTemplateId,
    required TransportVertical vertical,
    required SLAPenalties penalties,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (contractId.isEmpty) {
      throw const DomainException('contractId must not be empty');
    }
    if (name.trim().isEmpty) {
      throw const DomainException('ServiceManifest name must not be empty');
    }
    if (name.length > 150) {
      throw const DomainException(
        'ServiceManifest name must not exceed 150 characters',
      );
    }

    return ServiceManifest._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      contractId: contractId,
      name: name,
      description: description,
      slaTemplateId: slaTemplateId,
      vertical: vertical,
      penalties: penalties,
      createdAtUtc:
          StaticDateTimeProvider.instance?.nowUtc() ?? DateTime.now().toUtc(),
    );
  }

  /// Reconstitutes from persistence without re-validating invariants.
  static ServiceManifest reconstitute({
    required String id,
    required String organizationId,
    required String contractId,
    required String name,
    String? description,
    String? slaTemplateId,
    required TransportVertical vertical,
    required SLAPenalties penalties,
    required DateTime createdAtUtc,
  }) {
    return ServiceManifest._(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      name: name,
      description: description,
      slaTemplateId: slaTemplateId,
      vertical: vertical,
      penalties: penalties,
      createdAtUtc: createdAtUtc,
    );
  }

  @override
  List<Object?> get props => [id];
}
