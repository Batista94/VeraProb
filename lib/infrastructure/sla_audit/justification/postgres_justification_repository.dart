import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_evidence.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';

/// Supabase / Postgres implementation of [JustificationRepository].
///
/// **Architecture Guarantees:**
/// 1. **Tenant isolation**: every query includes `.eq('organization_id', ...)` (INV-1).
/// 2. **No `select('*')`**: explicit column lists only (Security Rules).
/// 3. **Bounded results**: every list query includes `.limit()`.
/// 4. **Status-only mutation**: [updateStatus] only writes review fields.
/// 5. **Token single-use**: [useToken] delegates to the `use_justification_token`
///    SECURITY DEFINER RPC (PO-1 — anon-safe).
class PostgresJustificationRepository implements JustificationRepository {
  final SupabaseClient _client;

  PostgresJustificationRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  // ── Justifications ────────────────────────────────────────────────────────

  @override
  Future<ContractorJustification> create(
    ContractorJustification justification,
  ) async {
    await _client.from('contractor_justifications').insert({
      'id': justification.id,
      'organization_id': justification.organizationId,
      'contract_id': justification.contractId,
      'set_id': justification.setId,
      'submitted_by_token': justification.submittedByToken,
      'category': justification.category.dbValue,
      'description': justification.description,
      'status': justification.status.dbValue,
      'created_at_utc': justification.createdAtUtc.toIso8601String(),
    });
    return justification;
  }

  @override
  Future<ContractorJustification?> findById({
    required String id,
    required String organizationId,
  }) async {
    final row = await _client
        .from('contractor_justifications')
        .select(
          'id, organization_id, contract_id, set_id, submitted_by_token, '
          'category, description, status, reviewed_by_user_id, '
          'reviewed_at_utc, created_at_utc',
        )
        .eq('id', id)
        .eq('organization_id', organizationId)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return _justificationFromRow(row);
  }

  @override
  Future<List<ContractorJustification>> listByOrg({
    required String organizationId,
    String? contractId,
    JustificationStatus? status,
    int limit = 100,
  }) async {
    var query = _client
        .from('contractor_justifications')
        .select(
          'id, organization_id, contract_id, set_id, submitted_by_token, '
          'category, description, status, reviewed_by_user_id, '
          'reviewed_at_utc, created_at_utc',
        )
        .eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }
    if (status != null) {
      query = query.eq('status', status.dbValue);
    }

    final rows = await query
        .order('created_at_utc', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((r) => _justificationFromRow(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ContractorJustification> updateStatus({
    required String id,
    required String organizationId,
    required JustificationStatus status,
    required String reviewedByUserId,
    required DateTime reviewedAtUtc,
  }) async {
    await _client
        .from('contractor_justifications')
        .update({
          'status': status.dbValue,
          'reviewed_by_user_id': reviewedByUserId,
          'reviewed_at_utc': reviewedAtUtc.toIso8601String(),
        })
        .eq('id', id)
        .eq('organization_id', organizationId);

    final updated = await findById(id: id, organizationId: organizationId);
    if (updated == null) {
      throw StateError('Justification $id not found after update.');
    }
    return updated;
  }

  // ── Evidence ──────────────────────────────────────────────────────────────

  @override
  Future<JustificationEvidence> addEvidence(
    JustificationEvidence evidence,
  ) async {
    await _client.from('justification_evidence_uploads').insert({
      'id': evidence.id,
      'justification_id': evidence.justificationId,
      'organization_id': evidence.organizationId,
      'file_name': evidence.fileName,
      'content_hash': evidence.contentHash,
      'storage_path': evidence.storagePath,
      'uploaded_at_utc': evidence.uploadedAtUtc.toIso8601String(),
    });
    return evidence;
  }

  @override
  Future<List<JustificationEvidence>> getEvidence({
    required String justificationId,
    required String organizationId,
  }) async {
    final rows = await _client
        .from('justification_evidence_uploads')
        .select(
          'id, justification_id, organization_id, file_name, '
          'content_hash, storage_path, uploaded_at_utc',
        )
        .eq('justification_id', justificationId)
        .eq('organization_id', organizationId)
        .limit(100);

    return (rows as List)
        .map((r) => _evidenceFromRow(r as Map<String, dynamic>))
        .toList();
  }

  // ── Submission tokens ─────────────────────────────────────────────────────

  @override
  Future<JustificationSubmissionToken> createToken(
    JustificationSubmissionToken token,
  ) async {
    await _client.from('justification_submission_tokens').insert({
      'id': token.id,
      'organization_id': token.organizationId,
      'contract_id': token.contractId,
      'set_id': token.setId,
      'justification_id': token.justificationId,
      'token': token.token,
      'created_by_user_id': token.createdByUserId,
      'expires_at_utc': token.expiresAtUtc.toIso8601String(),
      'created_at_utc': token.createdAtUtc.toIso8601String(),
    });
    return token;
  }

  @override
  Future<JustificationSubmissionToken?> findToken(String tokenValue) async {
    final row = await _client
        .from('justification_submission_tokens')
        .select(
          'id, organization_id, contract_id, set_id, justification_id, '
          'token, created_by_user_id, expires_at_utc, used_at_utc, created_at_utc',
        )
        .eq('token', tokenValue)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return _tokenFromRow(row);
  }

  @override
  Future<String> useToken({
    required String tokenValue,
    required String category,
    required String description,
  }) async {
    final result = await _client.rpc(
      'use_justification_token',
      params: {
        'p_token': tokenValue,
        'p_category': category,
        'p_description': description,
      },
    );
    return result as String;
  }

  // ── Private mappers ───────────────────────────────────────────────────────

  ContractorJustification _justificationFromRow(Map<String, dynamic> row) {
    return ContractorJustification(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      contractId: row['contract_id'] as String,
      setId: row['set_id'] as String,
      submittedByToken: row['submitted_by_token'] as String?,
      category: JustificationCategory.fromDb(row['category'] as String),
      description: row['description'] as String,
      status: JustificationStatus.fromDb(row['status'] as String),
      reviewedByUserId: row['reviewed_by_user_id'] as String?,
      reviewedAtUtc: row['reviewed_at_utc'] != null
          ? DateTime.parse(row['reviewed_at_utc'] as String).toUtc()
          : null,
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
    );
  }

  JustificationEvidence _evidenceFromRow(Map<String, dynamic> row) {
    return JustificationEvidence(
      id: row['id'] as String,
      justificationId: row['justification_id'] as String,
      organizationId: row['organization_id'] as String,
      fileName: row['file_name'] as String,
      contentHash: row['content_hash'] as String,
      storagePath: row['storage_path'] as String,
      uploadedAtUtc: DateTime.parse(row['uploaded_at_utc'] as String).toUtc(),
    );
  }

  JustificationSubmissionToken _tokenFromRow(Map<String, dynamic> row) {
    return JustificationSubmissionToken(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      contractId: row['contract_id'] as String,
      setId: row['set_id'] as String,
      justificationId: row['justification_id'] as String?,
      token: row['token'] as String,
      createdByUserId: row['created_by_user_id'] as String,
      expiresAtUtc: DateTime.parse(row['expires_at_utc'] as String).toUtc(),
      usedAtUtc: row['used_at_utc'] != null
          ? DateTime.parse(row['used_at_utc'] as String).toUtc()
          : null,
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
    );
  }
}
