import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/sla_template_repository.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'projections/penalties_form_data.dart';

/// Application handler for creating or updating an [SlaTemplate].
///
/// Delegates creation to the domain factory and persistence to the repository.
class SaveSlaTemplateHandler {
  final SlaTemplateRepository _repository;

  SaveSlaTemplateHandler({required SlaTemplateRepository repository})
    : _repository = repository;

  /// Creates or updates an [SlaTemplate] and persists it.
  ///
  /// When [existingId] is provided the template is reconstituted with that ID
  /// (upsert), preserving the original record. Otherwise a new UUID is generated.
  ///
  /// Returns the saved template.
  Future<SlaTemplate> handle({
    required String organizationId,
    required String name,
    String? description,
    TransportVertical? vertical,
    required PenaltiesFormData penalties,
    String? existingId,
    DateTime? existingCreatedAt,
  }) async {
    final domainPenalties = penalties.toDomain();
    final template = existingId != null
        ? SlaTemplate.reconstitute(
            id: existingId,
            organizationId: organizationId,
            name: name,
            description: description,
            vertical: vertical,
            penalties: domainPenalties,
            createdAt: existingCreatedAt ?? DateTime.now().toUtc(),
          )
        : SlaTemplate.create(
            organizationId: organizationId,
            name: name,
            description: description,
            vertical: vertical,
            penalties: domainPenalties,
          );

    await _repository.save(template);
    return template;
  }
}
