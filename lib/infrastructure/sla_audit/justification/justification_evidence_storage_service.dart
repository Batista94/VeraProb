import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads raw evidence bytes to Supabase Storage and returns the storage path.
///
/// **Operator / authenticated path:** calls
/// `supabase.storage.from('justification-evidence').uploadBinary()` directly.
///
/// **Driver (anon) path:** calls the `get-justification-upload-url` Edge Function,
/// which validates the justification token and returns a signed upload URL.
/// The caller then POSTs bytes to that URL directly — no JWT required.
///
/// The SHA-256 [contentHash] is computed client-side and stored in
/// `justification_evidence_uploads.content_hash` (INV-8).
class JustificationEvidenceStorageService {
  static const _bucket = 'justification-evidence';

  final SupabaseClient client;

  JustificationEvidenceStorageService(this.client);

  /// Uploads [bytes] for an authenticated operator/admin user.
  ///
  /// [organizationId] and [justificationId] are path-prefixed to enforce
  /// per-tenant isolation at the storage layer.
  ///
  /// Returns the storage path of the uploaded object.
  Future<String> uploadAuthenticated({
    required String organizationId,
    required String justificationId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = '$organizationId/$justificationId/$fileName';
    await client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  /// Returns a signed upload URL for an anonymous driver submission.
  ///
  /// Calls the `get-justification-upload-url` Edge Function, which:
  /// 1. Validates the token is active and belongs to the justification.
  /// 2. Returns a pre-signed URL the driver can POST to directly.
  ///
  /// The caller must POST bytes to the returned [url].
  Future<({String url, String storagePath})> getSignedUploadUrl({
    required String justificationToken,
    required String fileName,
  }) async {
    final response = await client.functions.invoke(
      'get-justification-upload-url',
      body: {'token': justificationToken, 'fileName': fileName},
    );

    final data = response.data as Map<String, dynamic>;
    return (
      url: data['url'] as String,
      storagePath: data['storagePath'] as String,
    );
  }
}
