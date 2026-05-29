import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/sla_audit/clone_sla_template_handler.dart';
import 'package:veraprob/application/sla_audit/save_sla_template_handler.dart';
import 'package:veraprob/application/sla_audit/sla_template_presets.dart';
import 'package:veraprob/domain/sla_audit/i_sla_template_audit_log_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/sla_template_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_audit_log_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_template_audit_log_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_template_repository.dart';
import 'auth_providers.dart';
import 'contract_providers.dart';
import 'shared_providers.dart';

// ── Repository ───────────────────────────────────────────────

final slaTemplateRepositoryProvider = Provider<SlaTemplateRepository>((ref) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemorySlaTemplateRepository(),
    PersistenceMode.postgres => PostgresSlaTemplateRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

final slaTemplateAuditLogRepositoryProvider =
    Provider<ISlaTemplateAuditLogRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory => InMemorySlaTemplateAuditLogRepository(),
        PersistenceMode.postgres => PostgresSlaTemplateAuditLogRepository(
          ref.watch(supabaseClientProvider),
        ),
      };
    });

// ── Handlers ─────────────────────────────────────────────────

final saveSlaTemplateHandlerProvider = Provider<SaveSlaTemplateHandler>((ref) {
  return SaveSlaTemplateHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    repository: ref.watch(slaTemplateRepositoryProvider),
    auditLog: ref.watch(slaTemplateAuditLogRepositoryProvider),
    clock: ref.watch(dateTimeProviderProvider),
  );
});

final cloneSlaTemplateHandlerProvider = Provider<CloneSlaTemplateHandler>((
  ref,
) {
  return CloneSlaTemplateHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    repository: ref.watch(slaTemplateRepositoryProvider),
  );
});

// ── System presets ───────────────────────────────────────────

/// System-provided SLA template presets (read-only, not persisted in DB).
final slaTemplatePresetsProvider = Provider<List<SlaTemplateView>>((ref) {
  return SlaTemplatePresets.systemPresets()
      .map(SlaTemplateView.fromDomain)
      .toList();
});

// ── Org templates ────────────────────────────────────────────

/// All [SlaTemplate]s for the current organization, ordered by name.
final slaTemplatesProvider = FutureProvider<List<SlaTemplateView>>((ref) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return const [];

  final templates = await ref
      .watch(slaTemplateRepositoryProvider)
      .findByOrganization(orgId);
  return templates.map(SlaTemplateView.fromDomain).toList();
});

/// Merges system presets + org templates into a single list.
/// Presets appear first, then org templates sorted by name.
final allTemplatesProvider = FutureProvider<List<SlaTemplateView>>((ref) async {
  final presets = ref.watch(slaTemplatePresetsProvider);
  final orgTemplates = await ref.watch(slaTemplatesProvider.future);
  return [...presets, ...orgTemplates];
});

/// Finds a template by [id] — checks presets first, then org templates.
final slaTemplateByIdProvider = FutureProvider.family<SlaTemplateView?, String>(
  (ref, id) async {
    if (SlaTemplatePresets.isPreset(id)) {
      final domain = SlaTemplatePresets.findById(id);
      return domain != null ? SlaTemplateView.fromDomain(domain) : null;
    }
    final orgId = ref.watch(currentOrganizationIdProvider);
    if (orgId == null) return null;
    final domain = await ref
        .watch(slaTemplateRepositoryProvider)
        .findById(id, organizationId: orgId);
    return domain != null ? SlaTemplateView.fromDomain(domain) : null;
  },
);

// ── Mutations ────────────────────────────────────────────────

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
