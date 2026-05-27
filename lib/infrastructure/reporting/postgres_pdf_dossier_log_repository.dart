import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/reporting/i_pdf_dossier_log_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Supabase-backed implementation of [IPdfDossierLogRepository].
///
/// INV-1: [organizationId] comes from the command (JWT-verified upstream) —
///        never derived from [auth.uid()].
/// INV-3: INSERT only — no UPDATE or DELETE on forensic log entries.
/// INV-26: [PostgresErrorInterceptor] maps all PostgREST error codes to
///         domain exceptions — no raw DB codes reach the caller.
class PostgresPdfDossierLogRepository
    with PostgresErrorInterceptor
    implements IPdfDossierLogRepository {
  final SupabaseClient _client;

  const PostgresPdfDossierLogRepository(this._client);

  @override
  Future<void> logGeneration({
    required String organizationId,
    required String slaLedgerEntryId,
    required String documentHash,
    required String operatorId,
  }) async {
    try {
      await _client.from('pdf_dossier_logs').insert({
        'organization_id': organizationId,
        'sla_ledger_entry_id': slaLedgerEntryId,
        'document_hash_sha256': documentHash,
        'generated_by': operatorId,
      });
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'pdf_dossier_log',
        resourceId: slaLedgerEntryId,
      );
    }
  }
}
