import '../../domain/sla_audit/sla_penalties.dart';
import '../../domain/sla_audit/sla_template.dart';
import '../../domain/sla_audit/sla_template_repository.dart';
import '../../domain/sla_audit/transport_vertical.dart';

/// Application handler for creating or updating an [SlaTemplate].
///
/// Delegates creation to the domain factory and persistence to the repository.
class SaveSlaTemplateHandler {
  final SlaTemplateRepository _repository;

  SaveSlaTemplateHandler({required SlaTemplateRepository repository})
    : _repository = repository;

  /// Creates a new [SlaTemplate] and persists it.
  ///
  /// Returns the created template.
  Future<SlaTemplate> handle({
    required String organizationId,
    required String name,
    String? description,
    TransportVertical? vertical,
    required SLAPenalties penalties,
  }) async {
    final template = SlaTemplate.create(
      organizationId: organizationId,
      name: name,
      description: description,
      vertical: vertical,
      penalties: penalties,
    );

    await _repository.save(template);
    return template;
  }
}
