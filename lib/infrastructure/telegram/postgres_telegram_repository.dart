import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/telegram/compliance_check_result.dart';
import 'package:veraprob/domain/sla_audit/telegram/i_telegram_repository.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_link.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_upload.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase/Postgres implementation of [ITelegramRepository].
///
/// INV-1: All queries filter by organization_id.
/// INV-7: No DELETE or UPDATE calls — only INSERT and SELECT.
class PostgresTelegramRepository extends BasePostgresRepository
    implements ITelegramRepository {
  PostgresTelegramRepository(super.client);

  @override
  Future<TelegramBindingToken> createBindingToken(
    TelegramBindingToken token,
  ) async {
    try {
      await client.from('telegram_binding_tokens').insert({
        'id': token.id,
        'organization_id': token.organizationId,
        'driver_id': token.driverId,
        'created_by_user_id': token.createdByUserId,
        'code': token.code,
        'expires_at_utc': token.expiresAtUtc.toIso8601String(),
        'created_at_utc': token.createdAtUtc.toIso8601String(),
      });
      return token;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_binding_token',
      );
    }
  }

  @override
  Future<TelegramBindingToken?> findLatestTokenForDriver({
    required String driverId,
    required String organizationId,
  }) async {
    try {
      final row = await client
          .from('telegram_binding_tokens')
          .select(
            'id, organization_id, driver_id, created_by_user_id, '
            'code, expires_at_utc, used_at_utc, created_at_utc',
          )
          .eq('driver_id', driverId)
          .eq('organization_id', organizationId)
          .order('created_at_utc', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return null;
      return _tokenFromRow(row);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_binding_token',
      );
    }
  }

  @override
  Future<bool> hasActiveBinding({
    required String driverId,
    required String organizationId,
  }) async {
    try {
      final row = await client
          .from('telegram_chat_bindings')
          .select('id')
          .eq('driver_id', driverId)
          .eq('organization_id', organizationId)
          .isFilter('unbound_at_utc', null)
          .limit(1)
          .maybeSingle();
      return row != null;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_chat_binding',
      );
    }
  }

  @override
  Future<List<TelegramEvidenceUpload>> findOrphanEvidences({
    required String organizationId,
  }) async {
    try {
      // Fetch uploads with requires_manual_link=true, embed links to filter client-side.
      // PostgREST LEFT JOIN: rows with no links return empty array for the relation.
      final rows = await client
          .from('telegram_evidence_uploads')
          .select(
            'id, organization_id, driver_id, chat_id, telegram_message_id, '
            'file_name, forensic_hash, storage_path, source, linked_set_id, '
            'uploaded_at_utc, telegram_message_date, requires_manual_link, '
            'mime_type, '
            'telegram_evidence_links(id, source), '
            'telegram_evidence_categories(category)',
          )
          .eq('organization_id', organizationId)
          .eq('requires_manual_link', true)
          .order('telegram_message_date', ascending: false);

      // Filter: only include uploads with no reconciliation links
      return (rows as List<dynamic>)
          .where((row) {
            final links = row['telegram_evidence_links'] as List<dynamic>?;
            return links == null || links.isEmpty;
          })
          .map((row) => _evidenceFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_evidence_upload',
      );
    }
  }

  @override
  Future<TelegramEvidenceLink> linkEvidenceToExecution({
    required String evidenceUploadId,
    required String executionSetId,
    required String organizationId,
    required String userId,
    String source = 'reconciliation',
  }) async {
    try {
      final row = await client
          .from('telegram_evidence_links')
          .insert({
            'organization_id': organizationId,
            'evidence_upload_id': evidenceUploadId,
            'execution_set_id': executionSetId,
            'linked_by_user_id': userId,
            'source': source,
          })
          .select()
          .single();

      return _linkFromRow(row);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'telegram_evidence_link',
      );
    }
  }

  TelegramBindingToken _tokenFromRow(Map<String, dynamic> row) {
    return TelegramBindingToken(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      driverId: row['driver_id'] as String,
      createdByUserId: row['created_by_user_id'] as String,
      code: row['code'] as String,
      expiresAtUtc: DateTime.parse(row['expires_at_utc'] as String).toUtc(),
      usedAtUtc: row['used_at_utc'] != null
          ? DateTime.parse(row['used_at_utc'] as String).toUtc()
          : null,
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
    );
  }

  TelegramEvidenceUpload _evidenceFromRow(Map<String, dynamic> row) {
    // PostgREST embedding: telegram_evidence_categories is a 0-or-1 element
    // list (UNIQUE FK). Extract category from first element if present.
    final catList = row['telegram_evidence_categories'] as List<dynamic>?;
    final category = (catList != null && catList.isNotEmpty)
        ? catList[0]['category'] as String?
        : null;

    // PostgREST embedding: telegram_evidence_links may contain 0+ elements.
    // Extract source from first link if present.
    final linkList = row['telegram_evidence_links'] as List<dynamic>?;
    final linkSource = (linkList != null && linkList.isNotEmpty)
        ? linkList[0]['source'] as String?
        : null;

    return TelegramEvidenceUpload(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      driverId: row['driver_id'] as String,
      chatId: row['chat_id'] as int,
      telegramMessageId: row['telegram_message_id'] as int,
      fileName: row['file_name'] as String,
      forensicHash: row['forensic_hash'] as String,
      storagePath: row['storage_path'] as String,
      source: row['source'] as String,
      linkedSetId: row['linked_set_id'] as String?,
      uploadedAtUtc: DateTime.parse(row['uploaded_at_utc'] as String).toUtc(),
      telegramMessageDate: DateTime.parse(
        row['telegram_message_date'] as String,
      ).toUtc(),
      requiresManualLink: row['requires_manual_link'] as bool,
      category: category,
      linkSource: linkSource,
      mimeType: row['mime_type'] as String?,
    );
  }

  TelegramEvidenceLink _linkFromRow(Map<String, dynamic> row) {
    return TelegramEvidenceLink(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      evidenceUploadId: row['evidence_upload_id'] as String,
      executionSetId: row['execution_set_id'] as String,
      linkedAtUtc: DateTime.parse(row['linked_at_utc'] as String).toUtc(),
      linkedByUserId: row['linked_by_user_id'] as String?,
      source: row['source'] as String,
    );
  }

  @override
  Future<ComplianceCheckResult> getComplianceStatus({
    required String organizationId,
    required String driverId,
  }) async {
    try {
      final data = await client.rpc(
        'get_trip_compliance_status',
        params: {'p_org_id': organizationId, 'p_driver_id': driverId},
      );
      return ComplianceCheckResult.fromJson((data as Map<String, dynamic>));
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'compliance_status');
    }
  }

  @override
  Future<Map<String, ComplianceCheckResult>> getBatchComplianceStatus({
    required String organizationId,
    required List<String> setIds,
  }) async {
    if (setIds.isEmpty) return {};
    try {
      final data = await client.rpc(
        'get_batch_compliance_status',
        params: {'p_org_id': organizationId, 'p_set_ids': setIds},
      );
      final list = data as List<dynamic>;
      return {
        for (final item in list)
          (item as Map<String, dynamic>)['set_id'] as String:
              ComplianceCheckResult.fromJson(item),
      };
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'batch_compliance_status',
      );
    }
  }

  @override
  Future<
    ({
      int queryCount,
      DateTime? lastQueriedAt,
      bool hadPendingItems,
      int forcedCompletions,
    })
  >
  getDriverStatusQueryCount({
    required String organizationId,
    required String driverId,
    required String setId,
  }) async {
    try {
      final data = await client.rpc(
        'get_driver_status_query_count',
        params: {
          'p_org_id': organizationId,
          'p_driver_id': driverId,
          'p_set_id': setId,
        },
      );
      final row = data as Map<String, dynamic>;
      return (
        queryCount: row['query_count'] as int,
        lastQueriedAt: row['last_queried_at'] != null
            ? DateTime.parse(row['last_queried_at'] as String).toUtc()
            : null,
        hadPendingItems: row['had_pending_items'] as bool,
        forcedCompletions: row['forced_completions'] as int,
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'driver_status_query_count',
      );
    }
  }
}
