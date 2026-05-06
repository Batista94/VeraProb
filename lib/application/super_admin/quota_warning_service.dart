import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/i_quota_alert_notifier.dart';
import 'package:veraprob/domain/admin/i_quota_alert_state_cache.dart';
import 'package:veraprob/domain/admin/quota_alert_context.dart';
import 'package:veraprob/domain/admin/quota_alert_payload.dart';
import 'package:veraprob/domain/admin/quota_warning.dart';

class QuotaWarningService {
  final SupabaseClient? _client;
  final IQuotaAlertNotifier? _notifier;
  final IQuotaAlertStateCache? _stateCache;

  static const _thresholds = [50, 80, 90, 99];

  QuotaWarningService(
    SupabaseClient client, {
    IQuotaAlertNotifier? notifier,
    IQuotaAlertStateCache? stateCache,
  }) : _client = client,
       _notifier = notifier,
       _stateCache = stateCache;

  QuotaWarningService.notifierOnly({
    required IQuotaAlertNotifier notifier,
    required IQuotaAlertStateCache stateCache,
  }) : _client = null,
       _notifier = notifier,
       _stateCache = stateCache;

  Future<List<QuotaWarning>> getActiveWarnings(String orgId) async {
    final data = await _client!
        .from('org_quota_warnings')
        .select()
        .eq('organization_id', orgId)
        .isFilter('resolved_at', null)
        .order('threshold', ascending: false);

    return (data as List)
        .map((row) => QuotaWarning.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<QuotaWarning?> getHighestWarning(String orgId, String resource) async {
    final data = await _client!
        .from('org_quota_warnings')
        .select()
        .eq('organization_id', orgId)
        .eq('resource', resource)
        .isFilter('resolved_at', null)
        .order('threshold', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return QuotaWarning.fromJson(data);
  }

  Future<void> checkAndDispatchAlerts(QuotaAlertContext ctx) async {
    final notifier = _notifier;
    final stateCache = _stateCache;
    if (notifier == null || stateCache == null) return;

    final usagePct = ctx.maxAllowed > 0
        ? (ctx.currentCount * 100 ~/ ctx.maxAllowed).clamp(0, 200)
        : 0;

    for (final threshold in _thresholds) {
      if (usagePct < threshold) continue;

      final alreadySent = await stateCache.wasAlertSent(
        orgId: ctx.orgId,
        resource: ctx.resource,
        threshold: threshold,
      );
      if (alreadySent) continue;

      final payload = QuotaAlertPayload(
        orgName: ctx.orgName,
        resource: ctx.resource,
        usagePct: usagePct,
        threshold: threshold,
        currentCount: ctx.currentCount,
        maxAllowed: ctx.maxAllowed,
        recipientEmails: List.unmodifiable(ctx.adminEmails),
      );

      try {
        await notifier.dispatch(payload);
        await stateCache.markAlertSent(
          orgId: ctx.orgId,
          resource: ctx.resource,
          threshold: threshold,
        );
      } catch (_) {}
    }
  }
}
