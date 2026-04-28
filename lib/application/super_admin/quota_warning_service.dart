import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/quota_warning.dart';

/// Service for querying active quota warnings for an organization.
///
/// Reads from org_quota_warnings table populated by DB triggers.
class QuotaWarningService {
  final SupabaseClient _client;

  QuotaWarningService(this._client);

  /// Get all active warnings for an organization.
  Future<List<QuotaWarning>> getActiveWarnings(String orgId) async {
    final data = await _client
        .from('org_quota_warnings')
        .select()
        .eq('organization_id', orgId)
        .order('threshold', ascending: false);

    return (data as List)
        .map((row) => QuotaWarning.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Get the highest threshold warning for a specific resource.
  Future<QuotaWarning?> getHighestWarning(String orgId, String resource) async {
    final data = await _client
        .from('org_quota_warnings')
        .select()
        .eq('organization_id', orgId)
        .eq('resource', resource)
        .order('threshold', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return QuotaWarning.fromJson(data);
  }
}
