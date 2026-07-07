import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Keeps client permission claims fresh (Pilar 2 §2.3).
///
/// Enterprise tier-1 staleness detection: a scoped Realtime push on the user's
/// own `user_tenant_roles` rows (assign/revoke) plus a bounded poll of the
/// authoritative `current_perms_v()` RPC (catches permission-matrix edits that
/// do not touch `user_tenant_roles`). Both converge on one reconcile: when the
/// DB version diverges from the token's `perms_v`, force a single
/// `refreshSession()` so the JWT re-aggregates permissions before the ~5-min TTL.
class PermissionsSyncController {
  PermissionsSyncController({
    required SupabaseClient client,
    required Future<int> Function() readDbVersion,
    required Future<void> Function() onRefresh,
    required int Function() readTokenVersion,
    Duration pollInterval = const Duration(seconds: 45),
  }) : _client = client,
       _readDbVersion = readDbVersion,
       _onRefresh = onRefresh,
       _readTokenVersion = readTokenVersion,
       _pollInterval = pollInterval;

  final SupabaseClient _client;
  final Future<int> Function() _readDbVersion;
  final Future<void> Function() _onRefresh;
  final int Function() _readTokenVersion;
  final Duration _pollInterval;

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  bool _isSyncing = false;
  bool _disposed = false;

  /// Subscribes to the scoped Realtime push and starts the bounded poll.
  void start(String userId) {
    _channel = _client
        .channel('perms-sync:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_tenant_roles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => unawaited(reconcile()),
        )
        .subscribe();

    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(reconcile()));
  }

  /// Compares the authoritative DB version against the token's `perms_v`; on
  /// divergence forces exactly one session refresh. The [_isSyncing] guard
  /// prevents overlapping runs and the refresh loop (Lesson 8).
  Future<void> reconcile() async {
    if (_disposed || _isSyncing) return;
    _isSyncing = true;
    try {
      final dbVersion = await _readDbVersion();
      if (_disposed) return;
      if (dbVersion != _readTokenVersion()) {
        await _onRefresh();
      }
    } catch (_) {
      // Transient RPC/network failure: the next poll retries. The ~5-min TTL
      // plus sensitive-role session-kill remain the revocation backstop.
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    final channel = _channel;
    if (channel != null) {
      _channel = null;
      unawaited(_client.removeChannel(channel));
    }
  }
}

/// Lifecycle owner for [PermissionsSyncController], scoped to the signed-in
/// tenant user. Rebuilds only when the user identity changes (login / logout /
/// switch) — token refreshes do not churn the subscription. Wildcard holders
/// (TENANT_ADMIN / SuperAdmin) never change permissions, so sync is skipped.
///
/// Mount by watching this provider from the authenticated shell (`AdminLayout`).
final permissionsSyncProvider = Provider<PermissionsSyncController?>((ref) {
  final userId = ref.watch(currentOperatorIdProvider);
  if (userId == null) return null;

  if (ref.read(currentPermissionsProvider).contains('*')) return null;

  final client = ref.read(supabaseClientProvider);
  final controller = PermissionsSyncController(
    client: client,
    readDbVersion: () async {
      final Object? raw = await client.rpc('current_perms_v');
      return raw is num ? raw.toInt() : 0;
    },
    onRefresh: () => ref.read(authRepositoryProvider).refreshSession(),
    readTokenVersion: () => ref.read(tokenPermsVersionProvider),
  );
  controller.start(userId);
  ref.onDispose(controller.dispose);
  return controller;
});
