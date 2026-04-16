/// Forensic Audit Signature: CX-05-v2.1
/// Remediation: Red Team ID 6 (Storage Cost Leak)
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb Business Maverick
///
/// Automated cleanup service for orphaned evidence files.
/// Processes the `evidence_deletion_queue` table and removes files from
/// Supabase Storage after the 7-day grace period expires.
///
/// **Defense-in-Depth Layer 5:** Lifecycle management occurs AFTER atomic
/// persistence. Files are only deleted if the justification was successfully
/// rejected/expired (no "ghost deletions" from concurrency conflicts).
///
/// **Cost Control:** Prevents unbounded storage growth by removing evidence
/// from rejected/expired justifications that will never be reviewed again.
library;

import 'dart:developer';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Manages evidence lifecycle to prevent storage cost leaks (Red Team ID 6).
///
/// Uses Service Role client to bypass RLS and access the deletion queue.
/// Standard users cannot query this table (INV-24).
class EvidenceCleanupService {
  final SupabaseClient _serviceRoleClient;
  final IDateTimeProvider _clock;

  /// Constructor requires a Service Role client to bypass RLS.
  ///
  /// **Security:** The deletion queue is invisible to standard users.
  /// Only Service Role and SuperAdmin can query pending deletions.
  EvidenceCleanupService(this._serviceRoleClient, this._clock);

  /// Processes expired evidence from the deletion queue.
  ///
  /// Queries `evidence_deletion_queue WHERE delete_after_utc <= NOW()`
  /// and removes files from Supabase Storage. Deletes queue entries after
  /// successful removal.
  ///
  /// Returns the count of files deleted.
  ///
  /// **Idempotency:** If Storage delete fails, the queue entry remains and
  /// will be retried on the next run. No silent data loss.
  Future<int> processExpiredEvidence({required String organizationId}) async {
    var deletedCount = 0;

    try {
      // Query expired evidence (Service Role bypasses RLS)
      final rows = await _serviceRoleClient
          .from('evidence_deletion_queue')
          .select('id, evidence_url')
          .eq('organization_id', organizationId)
          .isFilter('deleted_at', null)
          .lte('delete_after_utc', _clock.nowUtc().toIso8601String())
          .limit(100); // Process in batches to avoid timeout

      for (final row in rows as List) {
        final queueId = row['id'] as String;
        final evidenceUrl = row['evidence_url'] as String;

        try {
          // Extract storage path from URL
          // Format: https://[project].supabase.co/storage/v1/object/public/[bucket]/[path]
          final uri = Uri.parse(evidenceUrl);
          final pathSegments = uri.pathSegments;
          final bucketIndex = pathSegments.indexOf('public') + 1;
          if (bucketIndex > 0 && bucketIndex < pathSegments.length) {
            final bucket = pathSegments[bucketIndex];
            final filePath = pathSegments.sublist(bucketIndex + 1).join('/');

            // Delete from Supabase Storage
            await _serviceRoleClient.storage.from(bucket).remove([filePath]);

            // Mark as deleted in the queue instead of physical removal
            await _serviceRoleClient
                .from('evidence_deletion_queue')
                .update({'deleted_at': _clock.nowUtc().toIso8601String()})
                .eq('id', queueId);

            deletedCount++;
          }
        } catch (e) {
          // Log error but continue processing other files
          log(
            'EvidenceCleanupService: Failed to delete evidence $evidenceUrl: $e',
          );
        }
      }
    } catch (e) {
      log('EvidenceCleanupService: Failed to query deletion queue: $e');
    }

    return deletedCount;
  }
}
