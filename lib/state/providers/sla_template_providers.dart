import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/clone_sla_template_handler.dart';
import '../../application/sla_audit/save_sla_template_handler.dart';
import '../../application/sla_audit/sla_template_presets.dart';
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

// ── Handlers ─────────────────────────────────────────────────

final saveSlaTemplateHandlerProvider = Provider<SaveSlaTemplateHandler>((ref) {
  return SaveSlaTemplateHandler(
    repository: ref.watch(slaTemplateRepositoryProvider),
  );
});

final cloneSlaTemplateHandlerProvider = Provider<CloneSlaTemplateHandler>((
  ref,
) {
  return CloneSlaTemplateHandler(
    repository: ref.watch(slaTemplateRepositoryProvider),
  );
});

// ── System presets ───────────────────────────────────────────

/// System-provided SLA template presets (read-only, not persisted in DB).
final slaTemplatePresetsProvider = Provider<List<SlaTemplate>>((ref) {
  return SlaTemplatePresets.systemPresets();
});

// ── Org templates ────────────────────────────────────────────

/// All [SlaTemplate]s for the current organization, ordered by name.
final slaTemplatesProvider = FutureProvider<List<SlaTemplate>>((ref) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return const [];

  return ref.watch(slaTemplateRepositoryProvider).findByOrganization(orgId);
});

/// Merges system presets + org templates into a single list.
/// Presets appear first, then org templates sorted by name.
final allTemplatesProvider = FutureProvider<List<SlaTemplate>>((ref) async {
  final presets = ref.watch(slaTemplatePresetsProvider);
  final orgTemplates = await ref.watch(slaTemplatesProvider.future);
  return [...presets, ...orgTemplates];
});

/// Finds a template by [id] — checks presets first, then org templates.
final slaTemplateByIdProvider = FutureProvider.family<SlaTemplate?, String>((
  ref,
  id,
) async {
  if (SlaTemplatePresets.isPreset(id)) {
    return SlaTemplatePresets.findById(id);
  }
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return null;
  return ref
      .watch(slaTemplateRepositoryProvider)
      .findById(id, organizationId: orgId);
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
