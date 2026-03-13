import 'dart:collection';

import '../../domain/sla_audit/sla_template.dart';
import '../../domain/sla_audit/sla_template_repository.dart';

/// In-memory implementation of [SlaTemplateRepository].
///
/// Suitable for development and testing. Thread-safety is NOT guaranteed.
class InMemorySlaTemplateRepository implements SlaTemplateRepository {
  final Map<String, SlaTemplate> _store = {};

  @override
  Future<void> save(SlaTemplate template) async {
    _store[template.id] = template;
  }

  @override
  Future<List<SlaTemplate>> findByOrganization(String organizationId) async {
    final results = _store.values
        .where((t) => t.organizationId == organizationId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return UnmodifiableListView(results);
  }

  @override
  Future<void> delete(String id, {required String organizationId}) async {
    final template = _store[id];
    if (template != null && template.organizationId == organizationId) {
      _store.remove(id);
    }
  }
}
