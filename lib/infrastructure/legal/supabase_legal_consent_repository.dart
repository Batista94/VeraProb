import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/legal/i_legal_consent_repository.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/legal/legal_document.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Supabase RPC implementation of [ILegalConsentRepository].
class SupabaseLegalConsentRepository
    with PostgresErrorInterceptor
    implements ILegalConsentRepository {
  final SupabaseClient _client;

  SupabaseLegalConsentRepository(this._client);

  @override
  Future<LegalConsentStatus> getConsentStatus() async {
    try {
      final raw = await _client.rpc('get_legal_consent_status');
      if (raw is! Map) {
        return const LegalConsentStatus(state: LegalConsentState.current);
      }
      final map = Map<String, dynamic>.from(raw);
      final status = map['status'] as String? ?? 'current';
      final docMap = map['document'];
      LegalDocument? doc;
      if (docMap is Map) {
        doc = _documentFromMap(Map<String, dynamic>.from(docMap));
      }
      return LegalConsentStatus(
        state: status == 'pending'
            ? LegalConsentState.pending
            : LegalConsentState.current,
        document: doc,
        priorVersion: map['prior_version'] as String?,
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'legal_document');
    }
  }

  @override
  Future<void> acceptTerms(String documentId) async {
    try {
      await _client.rpc(
        'accept_legal_terms',
        params: {'p_document_id': documentId},
      );
    } on PostgrestException catch (e) {
      throw _mapLegalRpcError(e, documentId);
    }
  }

  @override
  Future<void> withdrawConsent() async {
    try {
      await _client.rpc('withdraw_legal_consent');
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'legal_consent');
    }
  }

  LegalDocument _documentFromMap(Map<String, dynamic> m) {
    final published = m['published_at_utc'];
    final publishedAt = published is String
        ? DateTime.parse(published).toUtc()
        : DateTime.now().toUtc();
    return LegalDocument(
      id: m['id'] as String,
      docType: m['doc_type'] as String? ?? 'terms_of_use',
      version: m['version'] as String? ?? '',
      title: m['title'] as String? ?? '',
      bodyMarkdown: m['body_markdown'] as String? ?? '',
      contentSha256: m['content_sha256'] as String? ?? '',
      changelog: m['changelog'] as String?,
      publishedAtUtc: publishedAt,
    );
  }

  /// INV-26: P0002 / "Document not available" → same 404 surface as missing.
  Never _mapLegalRpcError(PostgrestException e, String documentId) {
    final message = e.message.toLowerCase();
    if (e.code == 'P0002' || message.contains('document not available')) {
      throw ResourceNotFoundException(
        resourceType: 'legal_document',
        resourceId: documentId,
        message: 'Document not available',
      );
    }
    throw mapPostgrestToDomainException(
      e,
      resourceType: 'legal_document',
      resourceId: documentId,
    );
  }
}
