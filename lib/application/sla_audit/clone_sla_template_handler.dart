import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/sla_template_repository.dart';
import 'sla_template_presets.dart';

/// Application handler for cloning an [SlaTemplate].
///
/// Supports cloning from both system presets (in-memory) and org-owned
/// templates (database). Creates a new org-owned copy.
class CloneSlaTemplateHandler {
  final SlaTemplateRepository _repository;

  CloneSlaTemplateHandler({required SlaTemplateRepository repository})
    : _repository = repository;

  /// Clones the template identified by [sourceId] into a new org-owned copy.
  ///
  /// If [sourceId] starts with `preset:`, reads from [SlaTemplatePresets].
  /// Otherwise, reads from the repository.
  ///
  /// Throws [DomainException] if the source is not found.
  /// Returns the newly created (cloned) template.
  Future<SlaTemplate> handle({
    required String sourceId,
    required String organizationId,
    String? nameOverride,
  }) async {
    final source = await _resolveSource(sourceId, organizationId);
    if (source == null) {
      throw const DomainException('Template de origem não encontrado.');
    }

    final clonedName = nameOverride ?? '${source.name} (Cópia)';

    final clone = SlaTemplate.create(
      organizationId: organizationId,
      name: clonedName,
      description: source.description,
      vertical: source.vertical,
      penalties: source.penalties,
    );

    await _repository.save(clone);
    return clone;
  }

  Future<SlaTemplate?> _resolveSource(
    String sourceId,
    String organizationId,
  ) async {
    if (SlaTemplatePresets.isPreset(sourceId)) {
      return SlaTemplatePresets.findById(sourceId);
    }
    return _repository.findById(sourceId, organizationId: organizationId);
  }
}
