import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sla_audit/sla_template.dart';
import '../../domain/sla_audit/sla_template_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/in_memory_sla_template_repository.dart';
import '../../infrastructure/sla_audit/postgres_sla_template_repository.dart';
import 'auth_providers.dart';

// ── Repository ───────────────────────────────────────────────

final slaTemplateRepositoryProvider = Provider<SlaTemplateRepository>((ref) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemorySlaTemplateRepository(),
    PersistenceMode.postgres => PostgresSlaTemplateRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── Template list ────────────────────────────────────────────

/// All [SlaTemplate]s for the current organization, ordered by name.
final slaTemplatesProvider = FutureProvider<List<SlaTemplate>>((ref) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return const [];

  return ref.watch(slaTemplateRepositoryProvider).findByOrganization(orgId);
});

// ── Mutations ────────────────────────────────────────────────

/// Saves a template and invalidates the list cache.
Future<void> saveSlaTemplate(SlaTemplate template, WidgetRef ref) async {
  await ref.read(slaTemplateRepositoryProvider).save(template);
  ref.invalidate(slaTemplatesProvider);
}

/// Deletes a template and invalidates the list cache.
Future<void> deleteSlaTemplate(
  String templateId,
  String organizationId,
  WidgetRef ref,
) async {
  await ref
      .read(slaTemplateRepositoryProvider)
      .delete(templateId, organizationId: organizationId);
  ref.invalidate(slaTemplatesProvider);
}
